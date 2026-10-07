import 'package:flutter_test/flutter_test.dart';
import 'package:luma/domain/api_key.dart';

void main() {
  test('an OpenRouter key shape passes, surrounding space is dropped', () {
    const key = 'sk-or-v1-0123456789abcdef0123456789abcdef';
    expect(parseApiKey(key), key);
    expect(parseApiKey('  $key\n'), key);
    expect(parseApiKey('sk-or-abc_DEF-123456'), 'sk-or-abc_DEF-123456');
  });

  test('anything else is not a key', () {
    for (final junk in [
      '',
      'halo dunia',
      'sk-or-',
      'sk-or-short',
      'sk-abc123456789012345', // another vendor's prefix
      'Bearer sk-or-v1-0123456789abcdef',
      'sk-or-v1-0123 456789abcdef', // space inside
      '"sk-or-v1-0123456789abcdef"',
      'sk-or-v1-0123456789abcdef!',
      'https://openrouter.ai/keys',
    ]) {
      expect(parseApiKey(junk), isNull, reason: junk);
    }
  });
}
