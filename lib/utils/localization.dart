import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'translations/id.dart';
import 'translations/en.dart';

const Map<String, Map<String, String>> localizedStrings = {
  'id': translationsId,
  'en': translationsEn,
};

extension LocalizationContext on BuildContext {
  String translate(String key) {
    final settings = Provider.of<SettingsProvider>(this, listen: false);
    final lang = settings.language;
    return localizedStrings[lang]?[key] ?? key;
  }
}
