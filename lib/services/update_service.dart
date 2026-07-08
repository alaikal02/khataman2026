import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static const String _githubLatestReleaseUrl =
      'https://api.github.com/repos/alaikal02/khataman2026/releases/latest';

  /// Checks if a new app version is available on GitHub Releases.
  /// Returns a map of release info if an update is available, or null otherwise.
  static Future<Map<String, dynamic>?> checkUpdate() async {
    if (kIsWeb) return null;

    try {
      final client = HttpClient();
      // Configure user-agent to prevent GitHub API rejection
      client.userAgent = 'alaikal02-khataman2026-app';
      
      final request = await client.getUrl(Uri.parse(_githubLatestReleaseUrl));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        return null;
      }

      final jsonString = await response.transform(utf8.decoder).join();
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      final serverTag = data['tag_name'] as String? ?? '';
      if (serverTag.isEmpty) return null;

      // Get current local version name (e.g. "1.15.4")
      final packageInfo = await PackageInfo.fromPlatform();
      final localVersion = packageInfo.version;

      if (isNewerVersion(serverTag, localVersion)) {
        // Look for apk asset
        String downloadUrl = data['html_url'] as String? ?? 'https://github.com/alaikal02/khataman2026/releases';
        final assets = data['assets'] as List<dynamic>?;
        if (assets != null) {
          for (final asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.toLowerCase().endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] as String;
              break;
            }
          }
        }

        final changelog = data['body'] as String?;
        // Check if changelog contains a special force update tag, e.g. "[force]"
        final isForceUpdate = changelog?.contains('[force]') ?? false;

        return {
          'version_name': serverTag.toLowerCase().replaceAll('v', '').trim(),
          'download_url': downloadUrl,
          'changelog': changelog,
          'is_force_update': isForceUpdate,
        };
      }
    } catch (e) {
      debugPrint('Error checking updates from GitHub: $e');
    }

    return null;
  }

  /// Helper logic to determine if the server version is newer than the local version.
  static bool isNewerVersion(String serverVersion, String localVersion) {
    final cleanServer = serverVersion.toLowerCase().replaceAll('v', '').trim();
    final cleanLocal = localVersion.toLowerCase().replaceAll('v', '').trim();

    final serverParts = cleanServer.split('.');
    final localParts = cleanLocal.split('.');

    for (int i = 0; i < 3; i++) {
      final s = i < serverParts.length ? (int.tryParse(serverParts[i]) ?? 0) : 0;
      final l = i < localParts.length ? (int.tryParse(localParts[i]) ?? 0) : 0;
      if (s > l) return true;
      if (s < l) return false;
    }
    return false;
  }
}
