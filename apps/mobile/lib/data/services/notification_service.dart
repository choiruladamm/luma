import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifikasi lokal (docs/discover.md): dipakai cuma buat "X udah masuk
/// rak" pas app di latar. Izin diminta pas download pertama mulai, bukan pas
/// app dibuka.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  var _ready = false;

  /// [onTap] dapet payload notifikasi yang ditap pas app lagi jalan.
  Future<void> init(void Function(String payload) onTap) async {
    if (_ready) return;
    _ready = true;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        if (r.payload case final p? when p.isNotEmpty) onTap(p);
      },
    );
  }

  /// iOS: alert + suara. Android 13+: POST_NOTIFICATIONS. Di bawah itu /
  /// platform lain: dianggap boleh.
  Future<bool> requestPermission() async {
    final ios = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true);
    final android = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    return (ios ?? android) ?? true;
  }

  Future<void> show({
    required int id,
    required String title,
    required String channelName,
    required String channelDescription,
    String? body,
    String? payload,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'unduhan',
        channelName,
        channelDescription: channelDescription,
        channelAction: AndroidNotificationChannelAction.update,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
    payload: payload,
  );
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
