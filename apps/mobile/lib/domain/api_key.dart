/// Shape of an OpenRouter API key: `sk-or-` + letters/digits/`-`/`_`, no spaces.
/// Checks the shape only (no server call), to reject garbage text before it is
/// saved. Null = not a key shape.
String? parseApiKey(String raw) {
  final key = raw.trim();
  return _shape.hasMatch(key) ? key : null;
}

final _shape = RegExp(r'^sk-or-[A-Za-z0-9_-]{8,}$');
