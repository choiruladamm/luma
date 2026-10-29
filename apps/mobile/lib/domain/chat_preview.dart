import 'dart:convert';

import 'models/book_chat.dart';

/// Shared by complete-answer validation and completed provisional paragraphs.
ChatAnswerBlock chatAnswerPart(Object? value, List<ChatSource> sources) {
  if (value is! Map ||
      value['text'] is! String ||
      value['source_ids'] is! List) {
    throw const FormatException('Paragraf tidak valid');
  }
  final ids = value['source_ids'] as List;
  final byId = {for (final s in sources) s.id: s};
  if (ids.toSet().length != ids.length ||
      ids.any((id) => id is! String || !byId.containsKey(id))) {
    throw const FormatException('Sumber paragraf tidak valid');
  }
  final block = ChatAnswerBlock(
    text: (value['text'] as String).trim(),
    kind: ChatAnswerKind.parse(value['kind']),
    sources: [for (final id in ids) byId[id]!],
  );
  ChatAnswer(
    status: ChatAnswerStatus.answered,
    blocks: [block],
    formatVersion: 2,
  );
  return block;
}

/// A bounded incremental JSON reader. Preview is never a trusted answer.
/// Only direct root.parts[].text strings are projected; final validation is separate.
class ChatPreviewDecoder {
  ChatPreviewDecoder({this.sources});
  final List<ChatSource>? sources;
  final _stack = <_Frame>[];
  final _blocks = <ChatAnswerBlock>[];
  final _token = StringBuffer();
  bool invalid = false, _root = false, _done = false, _string = false;
  bool _key = false, _escape = false;
  String? _unicode;
  int? _high;
  int _size = 0;
  int? _textIndex;

  List<ChatAnswerBlock> get blocks => List.unmodifiable([
    for (final b in _blocks)
      if (invalid)
        ChatAnswerBlock(text: b.text, kind: b.kind, sources: [])
      else
        b,
  ]);

  void add(String delta) {
    if (invalid) return;
    _size += utf8.encode(delta).length;
    if (_size > 48000) {
      invalid = true;
      return;
    }
    try {
      for (final unit in delta.codeUnits) {
        _read(unit);
      }
      _project();
    } on FormatException {
      invalid = true;
    }
  }

  Never _fail() {
    _project();
    throw const FormatException('Preview JSON tidak valid');
  }

  bool _space(int c) => c == 32 || c == 10 || c == 13 || c == 9;

  void _read(int c) {
    if (_string) {
      if (_unicode != null) {
        final digit = int.tryParse(String.fromCharCode(c), radix: 16);
        if (digit == null) _fail();
        _unicode = '${_unicode!}${String.fromCharCode(c)}';
        if (_unicode!.length == 4) {
          _character(int.parse(_unicode!, radix: 16));
          _unicode = null;
        }
        return;
      }
      if (_escape) {
        _escape = false;
        if (c == 117) {
          _unicode = '';
          return;
        }
        final escaped = {
          34: 34,
          92: 92,
          47: 47,
          98: 8,
          102: 12,
          110: 10,
          114: 13,
          116: 9,
        }[c];
        if (escaped == null) _fail();
        _character(escaped);
        return;
      }
      if (c == 92) {
        _escape = true;
        return;
      }
      if (c == 34) {
        if (_high != null) _fail();
        _string = false;
        final value = _token.toString();
        _token.clear();
        if (_key) {
          final frame = _stack.last;
          if (!frame.keys.add(value)) _fail();
          frame.key = value;
          frame.state = _State.colon;
        } else {
          _value(value);
        }
        _textIndex = null;
        return;
      }
      if (c < 32) _fail();
      _character(c);
      return;
    }
    if (_token.isNotEmpty) {
      if (!_space(c) && c != 44 && c != 93 && c != 125) {
        _token.writeCharCode(c);
        return;
      }
      final value = jsonDecode(_token.toString());
      _token.clear();
      _value(value);
    }
    if (_space(c)) return;
    if (_done) _fail();
    if (_stack.isEmpty) {
      if (_root || c != 123) _fail();
      _root = true;
      _stack.add(_Frame(true, _Role.root));
      return;
    }
    final frame = _stack.last;
    if (c == 125 || c == 93) {
      if ((c == 125) != frame.object ||
          ![_State.first, _State.after].contains(frame.state)) {
        _fail();
      }
      _close();
      return;
    }
    if (frame.state == _State.after) {
      if (c != 44) _fail();
      frame.state = _State.next;
      return;
    }
    if (frame.state == _State.colon) {
      if (c != 58) _fail();
      frame.state = _State.value;
      return;
    }
    _key = frame.object && [_State.first, _State.next].contains(frame.state);
    if (_key && c != 34) _fail();
    if (!_key &&
        ![_State.first, _State.next, _State.value].contains(frame.state)) {
      _fail();
    }
    if (c == 34) {
      _string = true;
      _token.clear();
      if (!_key && frame.role == _Role.part && frame.key == 'text') {
        _textIndex = frame.index;
      }
      return;
    }
    if (c == 123 || c == 91) {
      if (_stack.length >= 32) _fail();
      var role = _Role.other;
      int? index;
      if (frame.role == _Role.root && frame.key == 'parts') {
        if (c != 91) _fail();
        role = _Role.parts;
      } else if (frame.role == _Role.parts) {
        if (c != 123 || _blocks.length >= 32) _fail();
        role = _Role.part;
        index = _blocks.length;
        _blocks.add(ChatAnswerBlock(text: '', sources: []));
      } else if (frame.role == _Role.part && frame.key == 'text') {
        _fail();
      }
      _stack.add(_Frame(c == 123, role, index: index));
      return;
    }
    if (c == 116 || c == 102 || c == 110 || c == 45 || c >= 48 && c <= 57) {
      if (frame.role == _Role.parts ||
          frame.role == _Role.part && frame.key == 'text') {
        _fail();
      }
      _token.writeCharCode(c);
      return;
    }
    _fail();
  }

  void _character(int c) {
    if (_high != null) {
      if (c < 0xdc00 || c > 0xdfff) _fail();
      _token.writeCharCode(_high!);
      _token.writeCharCode(c);
      _high = null;
    } else if (c >= 0xd800 && c <= 0xdbff) {
      _high = c;
    } else {
      if (c >= 0xdc00 && c <= 0xdfff) _fail();
      _token.writeCharCode(c);
    }
  }

  void _project() {
    final index = _textIndex;
    if (index == null) return;
    _blocks[index] = ChatAnswerBlock(
      text: _token.toString().trim(),
      sources: [],
    );
  }

  void _value(Object? value) {
    final frame = _stack.last;
    if (frame.object) {
      frame.map[frame.key!] = value;
      if (frame.role == _Role.part && frame.key == 'text') {
        if (value is! String) _fail();
        _blocks[frame.index!] = ChatAnswerBlock(text: value, sources: []);
      }
      if (frame.role == _Role.root && frame.key == 'parts' && value is! List) {
        _fail();
      }
    } else {
      frame.list.add(value);
    }
    frame.state = _State.after;
  }

  void _close() {
    final frame = _stack.removeLast();
    if (frame.role == _Role.part && sources != null) {
      _blocks[frame.index!] = chatAnswerPart(frame.map, sources!);
    }
    if (_stack.isEmpty) {
      _done = true;
    } else {
      _value(frame.object ? frame.map : frame.list);
    }
  }
}

enum _Role { root, parts, part, other }

enum _State { first, next, colon, value, after }

class _Frame {
  _Frame(this.object, this.role, {this.index});
  final bool object;
  final _Role role;
  final int? index;
  final keys = <String>{};
  final map = <String, Object?>{};
  final list = <Object?>[];
  String? key;
  _State state = _State.first;
}

/// Restored/terminal drafts expose text only, never trusted sources or history.
List<ChatAnswerBlock> chatDraftPreview(String raw) {
  final reader = ChatPreviewDecoder()..add(raw);
  return [
    for (final b in reader.blocks) ChatAnswerBlock(text: b.text, sources: []),
  ];
}
