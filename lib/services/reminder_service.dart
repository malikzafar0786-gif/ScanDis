import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Schedules on-device reminder notifications for bill due dates.
/// Fully local — no server, no internet needed for the reminder itself.
class ReminderService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// Uses permission_handler (already used elsewhere in the app for
  /// camera access) rather than the notifications plugin's own
  /// platform-specific permission classes, which have changed shape
  /// across versions — this keeps the request on one stable, well-known
  /// API instead.
  static Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Schedules a one-time reminder at 9 AM on [dueDate] for the given bill.
  /// [documentId]'s hashCode is used as the notification id so re-scheduling
  /// the same document's reminder replaces the old one instead of stacking.
  static Future<void> scheduleBillReminder({
    required String documentId,
    required String title,
    required DateTime dueDate,
  }) async {
    await init();

    final scheduledDate = tz.TZDateTime(tz.local, dueDate.year, dueDate.month, dueDate.day, 9);

    // Don't schedule reminders in the past.
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

    const androidDetails = AndroidNotificationDetails(
      'bill_reminders',
      'Bill Reminders',
      channelDescription: 'Reminders for scanned bill due dates',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());

    await _plugin.zonedSchedule(
      documentId.hashCode,
      'Bill Due Today: $title',
      "Don't forget to pay this bill.",
      scheduledDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelReminder(String documentId) async {
    await init();
    await _plugin.cancel(documentId.hashCode);
  }
}
