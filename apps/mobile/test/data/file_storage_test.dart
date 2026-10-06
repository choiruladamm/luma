import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/services/file_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late FileStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('luma_storage_');
    storage = FileStorage(root);
    await storage.ensureDirs();
  });
  tearDown(() => root.delete(recursive: true));

  test('creates books/ and covers/, idempotently', () async {
    await storage.ensureDirs();
    expect(await storage.booksDir.exists(), isTrue);
    expect(await storage.coversDir.exists(), isTrue);
  });

  test('resolves bare names under the current root', () async {
    await storage.writeBook('abc.epub', [1, 2, 3]);
    await storage.writeCover('abc.png', [4]);

    // A reinstall moves the container: same names, new root, still found.
    final moved = FileStorage(
      await root.rename(
        p.join(root.parent.path, '${p.basename(root.path)}_moved'),
      ),
    );
    root = moved.root;
    expect(await moved.book('abc.epub').readAsBytes(), [1, 2, 3]);
    expect(moved.cover('abc.png').path, p.join(root.path, 'covers', 'abc.png'));
  });

  test('deletes a book and its cover, skipping missing files', () async {
    await storage.writeBook('abc.epub', [1]);
    await storage.deleteBookFiles(fileName: 'abc.epub', coverName: 'abc.png');
    expect(await storage.book('abc.epub').exists(), isFalse);
  });

  test('rejects names that escape the folder', () {
    for (final bad in [
      '',
      '.',
      '..',
      '../luma.sqlite',
      '/etc/passwd',
      'a/b.epub',
    ]) {
      expect(() => storage.book(bad), throwsArgumentError, reason: bad);
    }
  });
}
