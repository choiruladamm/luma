import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/api_key_store.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('empty until saved; trimmed; blank deletes', () async {
    final store = ApiKeyStore();
    expect(await store.read(), isNull);
    await store.write('  sk-or-v1-abc \n');
    expect(await store.read(), 'sk-or-v1-abc');
    await store.write('   ');
    expect(await store.read(), isNull);
  });
}
