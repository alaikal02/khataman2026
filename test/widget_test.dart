import 'package:flutter_test/flutter_test.dart';
import 'package:khataman_quran/services/update_service.dart';

void main() {
  test('Khataman Quran basic smoke test', () {
    expect(true, isTrue);
  });

  group('UpdateService Tests', () {
    test('isNewerVersion returns true when server version is higher', () {
      expect(UpdateService.isNewerVersion('v1.16.0', '1.15.4'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewerVersion('1.15.5', '1.15.4'), isTrue);
    });

    test('isNewerVersion returns false when versions are equal', () {
      expect(UpdateService.isNewerVersion('v1.15.4', '1.15.4'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
    });

    test('isNewerVersion returns false when server version is lower', () {
      expect(UpdateService.isNewerVersion('v1.15.3', '1.15.4'), isFalse);
      expect(UpdateService.isNewerVersion('1.0.0', '1.1.0'), isFalse);
    });
  });
}
