import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// File EPUB / Markdown / PDF yang dipilih user (masih di folder sementara
/// picker, tetap ada sampai import selesai).
class PickedFile {
  const PickedFile({
    required this.name,
    required this.size,
    required this.read,
    this.path,
  });

  final String name;
  final int size;
  final Future<Uint8List> Function() read;

  /// Path lokal. PDF dibaca lewat path (bisa ratusan MB), bukan [read].
  final String? path;
}

class FilePickerService {
  const FilePickerService();

  /// Picker nyalin file pilihan ke cache app (PDF bisa puluhan MB). Dipanggil
  /// abis import beres / gagal; gagal hapus gak ngaruh ke apa-apa.
  Future<void> clearTemporaryFiles() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } on Object {
      // Platform tanpa cache picker, atau plugin belum nempel (test).
    }
  }

  /// File backup `.zip` (path lokal, dibaca streaming). Null = batal.
  Future<File?> pickBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = file?.path;
    return path == null ? null : File(path);
  }

  /// EPUB, PDF, atau Luma Markdown. Null = user batal milih.
  Future<PickedFile?> pickBook() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['epub', 'pdf', 'md', 'markdown'],
    );
    if (file == null) return null;
    return PickedFile(
      name: file.name,
      size: file.lengthSync() ?? await file.length() ?? 0,
      read: file.readAsBytes,
      path: file.path,
    );
  }
}

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const FilePickerService(),
);
