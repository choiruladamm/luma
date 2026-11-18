import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows local notifications (docs/discover.md), used only for the "book is on
/// the shelf" message while the app is in the background.
///
/// Permission is requested when the first download starts, not when the app opens.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  var _ready = false;

  /// Initializes the plugin; [onTap] receives the payload of a notification tapped while the app is running.
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

  /// Requests notification permission and returns whether it is granted.
  ///
  /// Asks for alert + sound on iOS and POST_NOTIFICATIONS on Android 13+; older
  /// Android and other platforms count as granted.
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
