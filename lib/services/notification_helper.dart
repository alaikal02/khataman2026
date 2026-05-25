import 'notification_helper_stub.dart'
    if (dart.library.html) 'notification_helper_web.dart';

class NotificationHelper {
  static Future<void> showWebNotification(String title, String body) async {
    await showNotificationImpl(title, body);
  }
}
