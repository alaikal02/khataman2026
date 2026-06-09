import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'prayer_time_service.dart';

/// Service for scheduling and managing Azan notifications
class AzanNotificationService {
  static final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  // SharedPreferences keys
  static const _keyAzanEnabled = 'azan_enabled';
  static const _keyAzanSubuh = 'azan_subuh';
  static const _keyAzanDzuhur = 'azan_dzuhur';
  static const _keyAzanAshar = 'azan_ashar';
  static const _keyAzanMaghrib = 'azan_maghrib';
  static const _keyAzanIsya = 'azan_isya';
  static const _keyAzanSound = 'azan_sound';

  // Notification IDs for each prayer (fixed IDs to allow cancel/update)
  static const _notifIdSubuh = 100;
  static const _notifIdDzuhur = 101;
  static const _notifIdAshar = 102;
  static const _notifIdMaghrib = 103;
  static const _notifIdIsya = 104;

  /// Initialize timezone database and notification plugin
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize timezone
      tz_data.initializeTimeZones();
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
      debugPrint('🕌 Timezone initialized: $timezoneName');

      // Initialize local notifications
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _notifPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Request Android notification permission
      final androidImpl = _notifPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.requestNotificationsPermission();
        await androidImpl.requestExactAlarmsPermission();
      }

      _isInitialized = true;
      debugPrint('🕌 Azan Notification Service initialized.');
    } catch (e) {
      debugPrint('🕌 Error initializing Azan service: $e');
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('🕌 Notification tapped: ${response.payload}');
    // Could navigate to prayer time screen in the future
  }

  /// Schedule azan notifications for a given day's prayer times
  static Future<void> scheduleAzanNotifications(DailyPrayerTimes prayerTimes) async {
    if (!_isInitialized) await initialize();

    final prefs = await SharedPreferences.getInstance();
    final masterEnabled = prefs.getBool(_keyAzanEnabled) ?? false;
    if (!masterEnabled) {
      debugPrint('🕌 Azan notifications are disabled.');
      return;
    }

    // Cancel all existing azan notifications before rescheduling
    await cancelAllAzanNotifications();

    final toggles = {
      'Subuh': prefs.getBool(_keyAzanSubuh) ?? true,
      'Dzuhur': prefs.getBool(_keyAzanDzuhur) ?? true,
      'Ashar': prefs.getBool(_keyAzanAshar) ?? true,
      'Maghrib': prefs.getBool(_keyAzanMaghrib) ?? true,
      'Isya': prefs.getBool(_keyAzanIsya) ?? true,
    };

    final idMap = {
      'Subuh': _notifIdSubuh,
      'Dzuhur': _notifIdDzuhur,
      'Ashar': _notifIdAshar,
      'Maghrib': _notifIdMaghrib,
      'Isya': _notifIdIsya,
    };

    final azanMessages = {
      'Subuh': 'حَيَّ عَلَى الصَّلَاة — Waktunya Shalat Subuh',
      'Dzuhur': 'حَيَّ عَلَى الصَّلَاة — Waktunya Shalat Dzuhur',
      'Ashar': 'حَيَّ عَلَى الصَّلَاة — Waktunya Shalat Ashar',
      'Maghrib': 'حَيَّ عَلَى الصَّلَاة — Waktunya Shalat Maghrib',
      'Isya': 'حَيَّ عَلَى الصَّلَاة — Waktunya Shalat Isya',
    };

    final now = DateTime.now();

    final sound = prefs.getString(_keyAzanSound) ?? 'default';

    String channelId = 'azan_channel_default';
    String channelName = 'Azan Shalat (Default)';
    AndroidNotificationSound? androidSound;
    bool playSound = true;

    if (sound == 'silent') {
      channelId = 'azan_channel_silent';
      channelName = 'Azan Shalat (Hening)';
      playSound = false;
    } else if (sound == 'makkah') {
      channelId = 'azan_channel_makkah';
      channelName = 'Azan Shalat (Makkah)';
      androidSound = const RawResourceAndroidNotificationSound('azan_makkah');
    } else if (sound == 'madinah') {
      channelId = 'azan_channel_madinah';
      channelName = 'Azan Shalat (Madinah)';
      androidSound = const RawResourceAndroidNotificationSound('azan_madinah');
    }

    for (final entry in prayerTimes.entries) {
      if (!entry.isFard) continue; // Only schedule for 5 fard prayers
      final isEnabled = toggles[entry.name] ?? false;
      final notifId = idMap[entry.name];
      if (!isEnabled || notifId == null) continue;

      // Only schedule if the prayer time is in the future
      if (entry.time.isAfter(now)) {
        final tzTime = tz.TZDateTime.from(entry.time, tz.local);
        final message = azanMessages[entry.name] ?? 'Waktunya Shalat';

        try {
          await _notifPlugin.zonedSchedule(
            notifId,
            '🕌 Azan ${entry.name}',
            message,
            tzTime,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channelId,
                channelName,
                channelDescription: 'Notifikasi azan untuk waktu shalat',
                importance: Importance.max,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
                category: AndroidNotificationCategory.alarm,
                visibility: NotificationVisibility.public,
                autoCancel: true,
                fullScreenIntent: true,
                playSound: playSound,
                sound: androidSound,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: playSound,
                sound: sound == 'silent'
                    ? null
                    : (sound == 'default'
                        ? null
                        : '$sound.mp3'),
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: null,
            payload: entry.name,
          );
          debugPrint('🕌 Scheduled azan for ${entry.name} at ${entry.time}');
        } catch (e) {
          debugPrint('🕌 Error scheduling ${entry.name}: $e');
        }
      }
    }
  }

  /// Cancel all scheduled azan notifications
  static Future<void> cancelAllAzanNotifications() async {
    await _notifPlugin.cancel(_notifIdSubuh);
    await _notifPlugin.cancel(_notifIdDzuhur);
    await _notifPlugin.cancel(_notifIdAshar);
    await _notifPlugin.cancel(_notifIdMaghrib);
    await _notifPlugin.cancel(_notifIdIsya);
    debugPrint('🕌 All azan notifications cancelled.');
  }

  // ── Persistence Helpers ────────────────────────────────

  static Future<bool> isAzanEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAzanEnabled) ?? false;
  }

  static Future<void> setAzanEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAzanEnabled, enabled);
    if (!enabled) {
      await cancelAllAzanNotifications();
    }
  }

  static Future<Map<String, bool>> getAzanToggles() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'Subuh': prefs.getBool(_keyAzanSubuh) ?? true,
      'Dzuhur': prefs.getBool(_keyAzanDzuhur) ?? true,
      'Ashar': prefs.getBool(_keyAzanAshar) ?? true,
      'Maghrib': prefs.getBool(_keyAzanMaghrib) ?? true,
      'Isya': prefs.getBool(_keyAzanIsya) ?? true,
    };
  }

  static Future<void> setAzanToggle(String prayer, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    switch (prayer) {
      case 'Subuh':
        await prefs.setBool(_keyAzanSubuh, enabled);
        if (!enabled) await _notifPlugin.cancel(_notifIdSubuh);
        break;
      case 'Dzuhur':
        await prefs.setBool(_keyAzanDzuhur, enabled);
        if (!enabled) await _notifPlugin.cancel(_notifIdDzuhur);
        break;
      case 'Ashar':
        await prefs.setBool(_keyAzanAshar, enabled);
        if (!enabled) await _notifPlugin.cancel(_notifIdAshar);
        break;
      case 'Maghrib':
        await prefs.setBool(_keyAzanMaghrib, enabled);
        if (!enabled) await _notifPlugin.cancel(_notifIdMaghrib);
        break;
      case 'Isya':
        await prefs.setBool(_keyAzanIsya, enabled);
        if (!enabled) await _notifPlugin.cancel(_notifIdIsya);
        break;
    }
  }

  static Future<String> getAzanSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAzanSound) ?? 'default';
  }

  static Future<void> setAzanSound(String sound) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAzanSound, sound);
  }

  /// Audio options for the dropdown
  static const azanSoundOptions = <String, String>{
    'default': 'Suara Default Sistem',
    'silent': 'Senyap (Getar Saja)',
    'makkah': 'Azan Makkah',
    'madinah': 'Azan Madinah',
  };
}
