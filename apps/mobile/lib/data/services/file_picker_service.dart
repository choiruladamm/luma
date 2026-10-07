import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// File EPUB yang dipilih user (masih di folder sementara picker).
class PickedFile {
  const PickedFile({
    required this.name,
    required this.size,
    required this.read,
  });

  final String name;
  final int size;
  final Future<Uint8List> Function() read;
}

class FilePickerService {
  const FilePickerService();

  /// File backup `.zip` (path lokal, dibaca streaming). Null = batal.
  Future<File?> pickBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = file?.path;
    return path == null ? null : File(path);
  }

  /// Null = user batal milih.
  Future<PickedFile?> pickEpub() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
    );
    if (file == null) return null;
    return PickedFile(
      name: file.name,
      size: file.lengthSync() ?? await file.length() ?? 0,
      read: file.readAsBytes,
    );
  }
}

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const FilePickerService(),
);
