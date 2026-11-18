import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Describes why an EPUB cannot be imported (Import board screens 16–18).
enum EpubError { corrupt, notEpub, drm }

class EpubException implements Exception {
  const EpubException(this.error, [this.detail]);

  final EpubError error;
  final String? detail;

  @override
  String toString() =>
      'EpubException(${error.name}${detail == null ? '' : ': $detail'})';
}

class EpubCover {
  const EpubCover(this.bytes, this.extension);

  final Uint8List bytes;

  /// The cover filename extension, such as `jpg` or `png`.
  final String extension;
}

/// Represents one TOC chapter spanning files from [startAnchor] to [endAnchor].
/// Null anchors indicate the start or end of the corresponding file.
class ChapterSource {
  const ChapterSource({
    required this.title,
    required this.files,
    this.section,
    this.startAnchor,
    this.endAnchor,
  });

  final String title;

  /// The nested parent TOC labels, outermost first, separated by ` › `.
  /// Null for top-level entries.
  final String? section;
  final List<String> files;
  final String? startAnchor;
  final String? endAnchor;
}

/// Holds plain EPUB data safe to return from `Isolate.run`.
class EpubOutline {
  const EpubOutline({
    required this.title,
    required this.author,
    required this.cover,
    required this.chapters,
    required this.html,
  });

  /// Null when metadata is empty; the caller falls back to the filename.
  final String? title;
  final String? author;
  final EpubCover? cover;

  /// Chapters in TOC order, matching `sortOrder`.
  final List<ChapterSource> chapters;

  /// HTML used by [chapters], keyed by path inside the zip.
  final Map<String, String> html;
}

const _fontObfuscation = {
  'http://www.idpf.org/2008/embedding',
  'http://ns.adobe.com/pdf/enc#RC',
};
const _epubNs = 'http://www.idpf.org/2007/ops';
final _path = p.posix;

/// Parses EPUB 2/3 metadata, cover, and chapters from the TOC.
/// Falls back from EPUB3 navigation to EPUB2 NCX, then to spine files.
/// Run synchronously through `Isolate.run(() => parseEpub(bytes))`.
/// Malformed TOC entries are skipped without failing the import.
EpubOutline parseEpub(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw EpubException(EpubError.corrupt, 'not a zip: $e');
  }

  String? read(String path) {
    final f = zip.find(path);
    return f == null || !f.isFile
        ? null
        : utf8.decode(f.content, allowMalformed: true);
  }

  final container = read('META-INF/container.xml');
  if (container == null) {
    // EPUB starts with an uncompressed `mimetype` file, even if the zip is truncated.
    throw _looksLikeEpub(bytes)
        ? const EpubException(EpubError.corrupt, 'unreadable EPUB zip')
        : const EpubException(EpubError.notEpub, 'no META-INF/container.xml');
  }
  _checkDrm(zip, read('META-INF/encryption.xml'));

  try {
    return _parse(zip, container, read);
  } on EpubException {
    rethrow;
  } catch (e) {
    throw EpubException(EpubError.corrupt, '$e');
  }
}

bool _looksLikeEpub(Uint8List bytes) {
  final head = latin1.decode(bytes.take(80).toList(), allowInvalid: true);
  return head.startsWith('PK') && head.contains('mimetypeapplication/epub+zip');
}

void _checkDrm(Archive zip, String? encryption) {
  // Adobe ADEPT & Apple FairPlay.
  if (zip.find('META-INF/rights.xml') != null ||
      zip.find('META-INF/sinf.xml') != null) {
    throw const EpubException(EpubError.drm);
  }
  if (encryption == null) return;
  // Font obfuscation is legal and common; other encryption locks the content.
  final algorithms = XmlDocument.parse(encryption)
      .findAllElements('EncryptionMethod', namespaceUri: '*')
      .map((e) => e.getAttribute('Algorithm'));
  if (algorithms.any((a) => !_fontObfuscation.contains(a))) {
    throw const EpubException(EpubError.drm);
  }
}

typedef _Item = ({String id, String path, String type, Set<String> props});
typedef _TocEntry = ({
  String title,
  String? section,
  String file,
  String? anchor,
});

EpubOutline _parse(
  Archive zip,
  String container,
  String? Function(String path) read,
) {
  final opfPath = XmlDocument.parse(container)
      .findAllElements('rootfile', namespaceUri: '*')
      .first
      .getAttribute('full-path')!;
  final opf = XmlDocument.parse(
    read(opfPath) ?? (throw EpubException(EpubError.corrupt, 'no $opfPath')),
  );
  final opfDir = _path.dirname(opfPath);

  Iterable<XmlElement> all(XmlNode n, String name) =>
      n.findAllElements(name, namespaceUri: '*');
  String? clean(String? s) {
    final t = s?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t == null || t.isEmpty ? null : t;
  }

  final title = all(opf, 'title').map((e) => clean(e.innerText)).nonNulls;
  final authors = all(opf, 'creator').map((e) => clean(e.innerText)).nonNulls;

  final items = <String, _Item>{
    for (final e in all(opf, 'item'))
      if (e.getAttribute('id') case final id?
          when e.getAttribute('href') != null)
        id: (
          id: id,
          path: _resolve(opfDir, e.getAttribute('href')!),
          type: e.getAttribute('media-type') ?? '',
          props: (e.getAttribute('properties') ?? '').split(' ').toSet(),
        ),
  };
  final spineEl = all(opf, 'spine').first;
  final spine = [
    for (final ref in all(spineEl, 'itemref'))
      if (ref.getAttribute('linear') != 'no')
        if (items[ref.getAttribute('idref')] case final item?)
          if (item.type.contains('html') && zip.find(item.path) != null)
            item.path,
  ];
  final spineIndex = {for (final (i, f) in spine.indexed) f: i};

  // Prefer EPUB3 navigation, falling back to EPUB2 NCX.
  List<_TocEntry> navToc() {
    final nav = items.values.where((i) => i.props.contains('nav')).firstOrNull;
    final doc = nav == null ? null : read(nav.path);
    if (doc == null) return const [];
    final navs = all(XmlDocument.parse(doc), 'nav');
    final toc =
        navs
            .where(
              (n) => n.getAttribute('type', namespaceUri: _epubNs) == 'toc',
            )
            .firstOrNull ??
        navs.firstOrNull;
    if (toc == null) return const [];
    final out = <_TocEntry>[];
    // Nested list labels become parent sections.
    void walk(XmlElement list, List<String> parents) {
      for (final li in list.findElements('li', namespaceUri: '*')) {
        final a = li.findElements('a', namespaceUri: '*').firstOrNull;
        final label =
            clean(a?.innerText) ??
            clean(
              li.findElements('span', namespaceUri: '*').firstOrNull?.innerText,
            );
        if (a?.getAttribute('href') case final href?) {
          out.add(
            _entry(
              label,
              parents.isEmpty ? null : parents.join(' › '),
              _path.dirname(nav!.path),
              href,
            ),
          );
        }
        for (final child in li.findElements('ol', namespaceUri: '*')) {
          walk(child, [...parents, ?label]);
        }
      }
    }

    for (final list in toc.findElements('ol', namespaceUri: '*')) {
      walk(list, const []);
    }
    if (out.isEmpty) {
      // Fall back to all links without hierarchy for malformed TOCs.
      return [
        for (final a in all(toc, 'a'))
          if (a.getAttribute('href') case final href?)
            _entry(clean(a.innerText), null, _path.dirname(nav!.path), href),
      ];
    }
    return out;
  }

  List<_TocEntry> ncxToc() {
    final ncxId = spineEl.getAttribute('toc');
    final ncx =
        items[ncxId] ??
        items.values
            .where((i) => i.type == 'application/x-dtbncx+xml')
            .firstOrNull;
    final doc = ncx == null ? null : read(ncx.path);
    if (doc == null) return const [];
    final navMap = all(XmlDocument.parse(doc), 'navMap').firstOrNull;
    if (navMap == null) return const [];
    final out = <_TocEntry>[];
    void walk(XmlElement parent, List<String> parents) {
      for (final point in parent.findElements('navPoint', namespaceUri: '*')) {
        final label = clean(
          point
              .findElements('navLabel', namespaceUri: '*')
              .firstOrNull
              ?.innerText,
        );
        if (point
                .findElements('content', namespaceUri: '*')
                .firstOrNull
                ?.getAttribute('src')
            case final src?) {
          out.add(
            _entry(
              label,
              parents.isEmpty ? null : parents.join(' › '),
              _path.dirname(ncx!.path),
              src,
            ),
          );
        }
        walk(point, [...parents, ?label]);
      }
    }

    walk(navMap, const []);
    return out;
  }

  var toc = navToc();
  if (toc.isEmpty) toc = ncxToc();

  // List.sort is unstable, so TOC order breaks ties within the same spine file.
  final seen = <String>{};
  final ordered = [
    for (final (i, e) in toc.indexed)
      if (spineIndex.containsKey(e.file) && seen.add('${e.file}#${e.anchor}'))
        (i, e),
  ];
  ordered.sort((a, b) {
    final bySpine = spineIndex[a.$2.file]!.compareTo(spineIndex[b.$2.file]!);
    return bySpine != 0 ? bySpine : a.$1.compareTo(b.$1);
  });
  final starts = [for (final (_, e) in ordered) e];

  final chapters = <ChapterSource>[];
  if (starts.isEmpty) {
    for (final (i, f) in spine.indexed) {
      chapters.add(ChapterSource(title: 'Bab ${i + 1}', files: [f]));
    }
  } else {
    for (final (i, s) in starts.indexed) {
      final from = spineIndex[s.file]!;
      final next = i + 1 < starts.length ? starts[i + 1] : null;
      final int to;
      String? endAnchor;
      if (next == null) {
        to = spine.length - 1;
      } else if (next.anchor != null) {
        to = spineIndex[next.file]!;
        endAnchor = next.anchor;
      } else {
        to = spineIndex[next.file]! - 1;
      }
      chapters.add(
        ChapterSource(
          title: s.title.isEmpty ? 'Bab ${i + 1}' : s.title,
          section: s.section,
          files: spine.sublist(from, to + 1),
          startAnchor: s.anchor,
          endAnchor: endAnchor,
        ),
      );
    }
  }

  final html = {
    for (final c in chapters)
      for (final f in c.files) f: read(f) ?? '',
  };

  return EpubOutline(
    title: title.firstOrNull,
    author: authors.isEmpty ? null : authors.join(', '),
    cover: _cover(zip, opf, items),
    chapters: chapters,
    html: html,
  );
}

_TocEntry _entry(String? title, String? section, String baseDir, String href) {
  final hash = href.indexOf('#');
  final file = hash == -1 ? href : href.substring(0, hash);
  final anchor = hash == -1 ? null : href.substring(hash + 1);
  return (
    title: title ?? '',
    section: section,
    file: _resolve(baseDir, file),
    anchor: anchor == null || anchor.isEmpty ? null : anchor,
  );
}

String _resolve(String baseDir, String href) =>
    _path.normalize(_path.join(baseDir, Uri.decodeFull(href)));

EpubCover? _cover(Archive zip, XmlDocument opf, Map<String, _Item> items) {
  // EPUB3 uses cover-image properties; EPUB2 uses a cover meta tag.
  final coverId = opf
      .findAllElements('meta', namespaceUri: '*')
      .where((m) => m.getAttribute('name') == 'cover')
      .firstOrNull
      ?.getAttribute('content');
  final item =
      items.values.where((i) => i.props.contains('cover-image')).firstOrNull ??
      items[coverId];
  if (item == null || !item.type.startsWith('image/')) return null;
  final file = zip.find(item.path);
  if (file == null) return null;
  final ext = switch (item.type) {
    'image/jpeg' => 'jpg',
    'image/svg+xml' => null, // Image.file can't render SVG.
    final t => t.substring('image/'.length),
  };
  return ext == null ? null : EpubCover(file.content, ext);
}
