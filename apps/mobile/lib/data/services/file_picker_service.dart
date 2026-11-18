import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Represents an EPUB, Markdown, or PDF file the user picked.
///
/// It still sits in the picker's temporary folder and stays there until the
/// import finishes.
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

  /// Local path; PDFs are read through the path (they can be hundreds of MB), not through [read].
  final String? path;
}

class FilePickerService {
  const FilePickerService();

  /// Deletes the copies the picker made in the app cache (a PDF can be tens of MB).
  ///
  /// Call it after an import finishes or fails; a failed delete is harmless.
  Future<void> clearTemporaryFiles() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } on Object {
      // The platform has no picker cache, or the plugin is not attached (tests).
    }
  }

  /// Picks a backup `.zip` (local path, read as a stream); returns null when cancelled.
  Future<File?> pickBackup() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = file?.path;
    return path == null ? null : File(path);
  }

  /// Picks an EPUB, PDF, or Luma Markdown book; returns null when the user cancels.
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
