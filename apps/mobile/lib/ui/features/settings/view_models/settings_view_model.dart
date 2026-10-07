import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/api_key_store.dart';
import '../../../../data/services/openrouter_service.dart';
import '../../../../domain/api_key.dart';
import '../../../../domain/models/ai_reply.dart';

/// Keadaan field API key di Pengaturan.
enum KeyStatus {
  /// Belum ada key, atau gak bisa ngecek (offline): cukup keterangan tempat
  /// nyimpennya, gak usah bikin panik.
  idle,

  /// Pengaturan baru dibuka, key yang kesimpen lagi dibaca & dicek ulang.
  /// Ditahan di sini supaya teks gak ganti-ganti: idle → valid.
  checking,

  /// Diterima OpenRouter (dan kesimpen).
  valid,

  /// Key yang udah kesimpen ditolak (401/403), mungkin udah dicabut.
  rejected,

  /// Key yang baru dimasukin ditolak OpenRouter, jadi gak disimpen.
  refused,

  /// Teksnya bukan bentuk API key OpenRouter, gak disimpen.
  badFormat,
}

/// Hasil cek OpenRouter terakhir buat key yang kesimpen. Hidup selama app
/// jalan, jadi buka Pengaturan lagi langsung nampilin hasilnya tanpa nunggu
/// cek ulang.
class KeyVerdict {
  ({String key, bool ok})? last;
}

final keyVerdictProvider = Provider<KeyVerdict>((ref) => KeyVerdict());

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
    ref.onDispose(() {
      _later?.cancel();
      _round++; // hasil cek yang telat jangan nyentuh state yang udah mati
    });
    unawaited(_checkStored());
    return switch (_verdict.last?.ok) {
      true => KeyStatus.valid,
      false => KeyStatus.rejected,
      null => KeyStatus.checking,
    };
  }

  KeyVerdict get _verdict => ref.read(keyVerdictProvider);

  /// Key yang udah kesimpen dicek ulang pas Pengaturan dibuka. Kalau hasil
  /// sebelumnya buat key yang sama udah ada, tampilannya tetap dan cek ulang
  /// jalan diam-diam (state cuma berubah kalau hasilnya beda).
  Future<void> _checkStored() async {
    final round = _round;
    final saved = await _store.read();
    if (round != _round) return;
    if (saved == null) {
      _verdict.last = null;
      state = KeyStatus.idle;
      return;
    }
    if (parseApiKey(saved) == null) {
      _verdict.last = null;
      state = KeyStatus.badFormat;
      return;
    }
    if (_verdict.last?.key != saved) {
      _verdict.last = null;
      state = KeyStatus.checking;
    }
    final ok = await _check(saved);
    if (round != _round) return;
    _remember(saved, ok);
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
      _verdict.last = null;
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
      _remember(key, ok);
      state = ok == true ? KeyStatus.valid : KeyStatus.idle;
    });
  }

  /// Offline (null) gak dicatat: gak ada hasil buat ditampilin.
  void _remember(String key, bool? ok) =>
      _verdict.last = ok == null ? null : (key: key, ok: ok);

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
