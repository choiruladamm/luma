import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File EPUB & cover di `Documents/books/` dan `Documents/covers/`.
///
/// DB cuma nyimpen nama file; path absolut dirakit di sini tiap kali, soalnya
/// container app iOS bisa pindah tiap update / install ulang.
class FileStorage {
  FileStorage(this.root);

  final Directory root;

  static Future<FileStorage> open() async {
    final storage = FileStorage(await getApplicationDocumentsDirectory());
    await storage.ensureDirs();
    return storage;
  }

  Directory get booksDir => Directory(p.join(root.path, 'books'));
  Directory get coversDir => Directory(p.join(root.path, 'covers'));

  Future<void> ensureDirs() => Future.wait([
    booksDir.create(recursive: true),
    coversDir.create(recursive: true),
  ]);

  File book(String fileName) => File(p.join(booksDir.path, _name(fileName)));
  File cover(String coverName) =>
      File(p.join(coversDir.path, _name(coverName)));

  Future<File> writeBook(String fileName, List<int> bytes) =>
      book(fileName).writeAsBytes(bytes, flush: true);
  Future<File> writeCover(String coverName, List<int> bytes) =>
      cover(coverName).writeAsBytes(bytes, flush: true);

  /// Hapus file buku & cover-nya. File yang udah gak ada dilewatin.
  Future<void> deleteBookFiles({String? fileName, String? coverName}) async {
    for (final f in [
      if (fileName != null) book(fileName),
      if (coverName != null) cover(coverName),
    ]) {
      if (await f.exists()) await f.delete();
    }
  }

  // Nama dari DB (atau dari backup yang di-restore) gak boleh nyasar keluar
  // folder lewat "../" atau path absolut.
  static String _name(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        p.basename(name) != name) {
      throw ArgumentError.value(name, 'name', 'must be a bare file name');
    }
    return name;
  }
}

/// Di-override di `main()` setelah [FileStorage.open].
final fileStorageProvider = Provider<FileStorage>(
  (ref) => throw UnimplementedError('override with FileStorage.open()'),
);
