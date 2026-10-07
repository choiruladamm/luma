import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../domain/api_key.dart';
import '../../../../domain/models/ai_reply.dart';

/// Keadaan field API key di Pengaturan.
enum KeyStatus {
  /// Belum ada key, lagi ngecek, atau gak bisa ngecek (offline): cukup
  /// keterangan tempat nyimpennya, gak usah bikin panik.
  idle,

  /// Diterima OpenRouter (dan kesimpen).
  valid,

  /// Key yang udah kesimpen ditolak (401/403), mungkin udah dicabut.
  rejected,

  /// Key yang baru dimasukin ditolak OpenRouter, jadi gak disimpen.
  refused,

  /// Teksnya bukan bentuk API key OpenRouter, gak disimpen.
  badFormat,
}

/// Isi field API key: nerima teks, ngecek bentuknya, nanya OpenRouter, baru
/// nyimpen ke Keychain. Teks ngawur dan key yang ditolak gak pernah
/// nimpa key yang udah kesimpen. Kosong = dihapus.
class ApiKeyEntry extends Notifier<KeyStatus> {
  static const pause = Duration(milliseconds: 600);

  Timer? _later;

  /// Tiap ketikan / hapus naikin angka ini; hasil cek yang telat dibuang.
  int _round = 0;

  ApiKeyStore get _store => ref.read(apiKeyStoreProvider);

  @override
  KeyStatus build() {
    ref.onDispose(() => _later?.cancel());
    unawaited(_checkStored());
    return KeyStatus.idle;
  }

  /// Key yang udah kesimpen dicek ulang pas Pengaturan dibuka.
  Future<void> _checkStored() async {
    final round = _round;
    final saved = await _store.read();
    if (saved == null || round != _round) return;
    if (parseApiKey(saved) == null) {
      state = KeyStatus.badFormat;
      return;
    }
    final ok = await _check(saved);
    if (round != _round) return;
    state = switch (ok) {
      true => KeyStatus.valid,
      false => KeyStatus.rejected,
      null => KeyStatus.idle,
    };
  }

  /// Teks field berubah (biasanya sekali paste).
  void edit(String text) {
    _later?.cancel();
    final round = ++_round;
    if (text.trim().isEmpty) {
      unawaited(_store.write(''));
      state = KeyStatus.idle;
      return;
    }
    final key = parseApiKey(text);
    if (key == null) {
      state = KeyStatus.badFormat;
      return;
    }
    state = KeyStatus.idle;
    _later = Timer(pause, () async {
      final ok = await _check(key);
      if (round != _round) return;
      if (ok == false) {
        state = KeyStatus.refused;
        return;
      }
      // Bentuknya bener dan gak ditolak (atau lagi offline): simpen.
      await _store.write(key);
      if (round != _round) return;
      state = ok == true ? KeyStatus.valid : KeyStatus.idle;
    });
  }

  /// Tombol hapus: key di Keychain ikut kehapus.
  void clear() => edit('');

  /// true = diterima, false = ditolak, null = gak bisa ngecek.
  Future<bool?> _check(String key) async {
    try {
      return await ref.read(openRouterServiceProvider).checkKey(key);
    } on AiException {
      return null;
    }
  }
}

final apiKeyEntryProvider =
    NotifierProvider.autoDispose<ApiKeyEntry, KeyStatus>(ApiKeyEntry.new);
