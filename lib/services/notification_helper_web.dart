// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> showNotificationImpl(String title, String body) async {
  try {
    if (html.Notification.permission == 'granted') {
      html.Notification(title, body: body);
    } else if (html.Notification.permission != 'denied') {
      final permission = await html.Notification.requestPermission();
      if (permission == 'granted') {
        html.Notification(title, body: body);
      }
    }
  } catch (e) {
    // Fail silently or log error if browser blocks notifications
    print('Web Notification Error: $e');
  }
}
