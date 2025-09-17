import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  static final NotificationDetails _defaultDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'aura_watch_alerts',
      'Price Alerts',
      channelDescription: 'Notifications when a watched token crosses a threshold',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
  );

  static Future<void> initialize() async {
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(initSettings);
  }

  static Future<void> showThresholdAlert(
      WatchedToken token,
      double priceUsd,
      ) async {
    final direction = token.alertAbove ? '≥' : '≤';
    final formattedPrice = priceUsd.toStringAsFixed(4);
    await _plugin.show(
      token.id.hashCode,
      '${token.label} price alert',
      'Price is $formattedPrice USD ($direction ${token.thresholdUsd})',
      _defaultDetails,
    );
  }
}
