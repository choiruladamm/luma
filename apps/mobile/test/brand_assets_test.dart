import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// (width, height, colour type) from a PNG header.
(int, int, int) png(File f) {
  final b = f.readAsBytesSync();
  final d = ByteData.sublistView(b);
  return (d.getUint32(16), d.getUint32(20), b[25]);
}

void main() {
  const icons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';

  test('app icon: light, dark and tinted 1024 files all exist', () {
    final images =
        (jsonDecode(File('$icons/Contents.json').readAsStringSync())
                as Map)['images']
            as List;
    final byAppearance = {
      for (final i in images.cast<Map>())
        (i['appearances'] as List?)?.first['value'] ?? 'light':
            i['filename'] as String,
    };
    expect(byAppearance.keys, {'light', 'dark', 'tinted'});
    for (final name in byAppearance.values) {
      expect(png(File('$icons/$name')).$1, 1024, reason: name);
      expect(png(File('$icons/$name')).$2, 1024, reason: name);
    }
  });

  test('the light icon has no alpha channel (the store rejects it)', () {
    // PNG colour type 2 = RGB, 6 = RGBA.
    expect(png(File('$icons/AppIcon-1024.png')).$3, 2);
    expect(png(File('$icons/AppIcon-1024-tinted.png')).$3, isNot(6));
  });

  test('launch screen is the plain canvas colour, no static logo', () {
    // The animation in Flutter starts empty; a static logo would flash.
    final board = File('ios/Runner/Base.lproj/LaunchScreen.storyboard')
        .readAsStringSync();
    expect(board, contains('name="LaunchBackground"'));
    expect(board, isNot(contains('<imageView')));
  });

  test('display name is Luma on both platforms', () {
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains('<key>CFBundleDisplayName</key>\n\t<string>Luma</string>'),
    );
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:label="Luma"'),
    );
  });
}
