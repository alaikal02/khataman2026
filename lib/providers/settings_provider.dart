import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class SettingsProvider extends ChangeNotifier {
  static const _keyTheme = 'theme_mode';
  static const _keyFontSize = 'font_size';
  static const _keyReminderEnabled = 'reminder_enabled';
  static const _keyReminderHour = 'reminder_hour';
  static const _keyReminderMinute = 'reminder_minute';
  static const _keyGroupNotif = 'group_notif';
  static const _keyDailyTarget = 'daily_target';

  ThemeMode _themeMode = ThemeMode.dark;
  double _fontSize = 1.0; // 0.85 = kecil, 1.0 = normal, 1.2 = besar
  bool _reminderEnabled = false;
  int _reminderHour = 20;
  int _reminderMinute = 0;
  bool _groupNotifEnabled = true;
  double _dailyTargetJuz = 1.0;

  ThemeMode get themeMode => _themeMode;
  double get fontSize => _fontSize;
  bool get reminderEnabled => _reminderEnabled;
  int get reminderHour => _reminderHour;
  int get reminderMinute => _reminderMinute;
  bool get groupNotifEnabled => _groupNotifEnabled;
  double get dailyTargetJuz => _dailyTargetJuz;

  String get dailyTargetJuzLabel {
    if (_dailyTargetJuz == 0.1) return '1/10 Juz (2 Halaman)';
    if (_dailyTargetJuz == 0.125) return '1/8 Juz (2.5 Halaman)';
    if (_dailyTargetJuz == 0.25) return '1/4 Juz (5 Halaman)';
    if (_dailyTargetJuz == 0.5) return '1/2 Juz (10 Halaman)';
    if (_dailyTargetJuz == 0.75) return '3/4 Juz (15 Halaman)';
    if (_dailyTargetJuz == 1.0) return '1 Juz (20 Halaman)';
    if (_dailyTargetJuz == 2.0) return '2 Juz (40 Halaman)';
    if (_dailyTargetJuz == 3.0) return '3 Juz (60 Halaman)';
    if (_dailyTargetJuz == 4.0) return '4 Juz (80 Halaman)';
    if (_dailyTargetJuz == 5.0) return '5 Juz (100 Halaman)';
    return '${_dailyTargetJuz.toStringAsFixed(_dailyTargetJuz % 1 == 0 ? 0 : 2)} Juz';
  }

  String get fontSizeLabel {
    if (_fontSize <= 0.85) return 'Kecil';
    if (_fontSize >= 1.2) return 'Besar';
    return 'Normal';
  }

  String get reminderTimeLabel =>
      '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}';

  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();

  SettingsProvider() {
    _load();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _notifPlugin.initialize(initSettings);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = ThemeMode.values[prefs.getInt(_keyTheme) ?? 0];
    _fontSize = prefs.getDouble(_keyFontSize) ?? 1.0;
    _reminderEnabled = prefs.getBool(_keyReminderEnabled) ?? false;
    _reminderHour = prefs.getInt(_keyReminderHour) ?? 20;
    _reminderMinute = prefs.getInt(_keyReminderMinute) ?? 0;
    _groupNotifEnabled = prefs.getBool(_keyGroupNotif) ?? true;
    final rawTarget = prefs.get(_keyDailyTarget);
    if (rawTarget is double) {
      _dailyTargetJuz = rawTarget;
    } else if (rawTarget is int) {
      _dailyTargetJuz = rawTarget.toDouble();
    } else {
      _dailyTargetJuz = 1.0;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTheme, mode.index);
  }

  Future<void> setFontSize(double size) async {
    _fontSize = size;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFontSize, size);
  }

  Future<void> setReminderEnabled(bool enabled) async {
    _reminderEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReminderEnabled, enabled);
    if (enabled) {
      await _scheduleReminder();
    } else {
      await _notifPlugin.cancelAll();
    }
  }

  Future<void> setReminderTime(int hour, int minute) async {
    _reminderHour = hour;
    _reminderMinute = minute;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReminderHour, hour);
    await prefs.setInt(_keyReminderMinute, minute);
    if (_reminderEnabled) await _scheduleReminder();
  }

  Future<void> setGroupNotif(bool enabled) async {
    _groupNotifEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGroupNotif, enabled);
  }

  Future<void> setDailyTarget(double juz) async {
    _dailyTargetJuz = juz;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyDailyTarget, juz);
  }

  Future<void> _scheduleReminder() async {
    await _notifPlugin.cancelAll();

    const androidDetails = AndroidNotificationDetails(
      'khataman_reminder',
      'Pengingat Khataman',
      channelDescription: 'Pengingat harian untuk membaca Al-Quran',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    // Show immediate test notification
    await _notifPlugin.show(
      0,
      '📖 Waktunya Membaca Al-Quran',
      'Jangan lupa target khataman hari ini. Bismillah!',
      const NotificationDetails(android: androidDetails),
    );
  }
}
