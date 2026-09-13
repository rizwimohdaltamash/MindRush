import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_plan.dart';

/// Schedules streak reminders through the OS.
///
/// No Firebase and no network: the device holds the streak, so it can remind
/// itself. Everything here is best-effort -- a phone that refuses to schedule
/// a notification must never stop a match from being played.
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler._(this._plugin);

  /// Reminder ids start here; each plan adds its own slot number, so the
  /// afternoon and evening nudges are separate notifications.
  static const int _firstReminderId = 1001;

  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'streak_reminders',
    'Streak reminders',
    channelDescription: 'Reminds you to play before your daily streak lapses.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const NotificationDetails _details = NotificationDetails(
    android: _android,
    iOS: DarwinNotificationDetails(),
  );

  final FlutterLocalNotificationsPlugin _plugin;

  /// Returns null when notifications are unavailable on this platform (web and
  /// desktop), so callers can fall back to [NoopScheduler].
  static Future<LocalNotificationScheduler?> create() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    tzdata.initializeTimeZones();

    final plugin = FlutterLocalNotificationsPlugin();
    final ready = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Asked for later, at a moment the player is enjoying the game --
          // a prompt on first launch gets refused far more often.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (ready == false) return null;
    return LocalNotificationScheduler._(plugin);
  }

  @override
  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    // Android 13+ requires this at runtime; older versions grant it at install
    // and return true here.
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> schedule(ReminderPlan plan) async {
    // Converted as an instant rather than a wall-clock time in a named zone:
    // Dart already knows the device's UTC offset, which avoids depending on a
    // platform channel just to learn the timezone name. The cost is that a
    // daylight-saving change between now and tomorrow evening would shift the
    // reminder by an hour, once a year.
    final at = tz.TZDateTime.from(plan.when.toUtc(), tz.UTC);

    await _plugin.zonedSchedule(
      id: _firstReminderId + plan.id,
      title: plan.title,
      body: plan.body,
      scheduledDate: at,
      notificationDetails: _details,
      // Inexact deliberately: an exact alarm needs the SCHEDULE_EXACT_ALARM
      // permission on Android 12+, and "about 8pm" is entirely good enough
      // for a nudge.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}
