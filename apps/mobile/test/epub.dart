import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds an in-memory EPUB from [files] (path → text) and [binary]
/// (path → bytes), with mimetype + container pointing at OEBPS/content.opf.
Uint8List buildEpub(
  Map<String, String> files, {
  Map<String, List<int>> binary = const {},
  bool container = true,
}) {
  final a = Archive()
    ..add(ArchiveFile.string('mimetype', 'application/epub+zip'));
  if (container) {
    a.add(
      ArchiveFile.string(
        'META-INF/container.xml',
        '<?xml version="1.0"?><container version="1.0" '
            'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="OEBPS/content.opf" '
            'media-type="application/oebps-package+xml"/></rootfiles>'
            '</container>',
      ),
    );
  }
  files.forEach((k, v) => a.add(ArchiveFile.string(k, v)));
  binary.forEach((k, v) => a.add(ArchiveFile.bytes(k, v)));
  return ZipEncoder().encodeBytes(a);
}

/// A content.opf with the given manifest `<item>`s and spine `<itemref>`s.
String opf({
  required String manifest,
  required String spine,
  String metadata = '',
  String spineAttrs = '',
}) =>
    '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">$metadata</metadata>'
    '<manifest>$manifest</manifest>'
    '<spine $spineAttrs>$spine</spine>'
    '</package>';

String xhtml(String body) =>
    '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml">'
    '<body>$body</body></html>';
