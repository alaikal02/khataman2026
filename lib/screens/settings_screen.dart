import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../services/azan_notification_service.dart';
import '../services/prayer_time_service.dart';
import '../utils/localization.dart';
import '../services/widget_update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _azanEnabled = false;
  Map<String, bool> _azanToggles = {
    'Subuh': true, 'Dzuhur': true, 'Ashar': true, 'Maghrib': true, 'Isya': true,
  };
  String _azanSound = 'default';
  String _calcMethod = 'muslim_world_league';
  String _madhab = 'syafii';
  String _appVersion = '1.13.0';

  @override
  void initState() {
    super.initState();
    _loadAzanSettings();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = packageInfo.version;
        });
      }
    } catch (e) {
      debugPrint('Error loading app version: $e');
    }
  }

  Future<void> _loadAzanSettings() async {
    final enabled = await AzanNotificationService.isAzanEnabled();
    final toggles = await AzanNotificationService.getAzanToggles();
    final sound = await AzanNotificationService.getAzanSound();
    final method = await PrayerTimeService.getCalcMethod();
    final madhab = await PrayerTimeService.getMadhab();
    if (mounted) {
      setState(() {
        _azanEnabled = enabled;
        _azanToggles = toggles;
        _azanSound = sound;
        _calcMethod = method;
        _madhab = madhab;
      });
    }
  }

  String _getTranslatedFontSizeLabel(BuildContext context, String rawLabel) {
    if (rawLabel == 'Kecil') return context.translate('font_size_small');
    if (rawLabel == 'Besar') return context.translate('font_size_large');
    return context.translate('font_size_normal');
  }

  String _getTranslatedPrayerName(BuildContext context, String rawName) {
    switch (rawName.toLowerCase()) {
      case 'subuh': return context.translate('prayer_subuh');
      case 'dzuhur': return context.translate('prayer_dzuhur');
      case 'ashar': return context.translate('prayer_ashar');
      case 'maghrib': return context.translate('prayer_maghrib');
      case 'isya': return context.translate('prayer_isya');
      default: return rawName;
    }
  }

  String _formatAzanTileTitle(BuildContext context, String rawPrayerName) {
    final format = context.translate('tile_azan_format');
    final translatedPrayer = _getTranslatedPrayerName(context, rawPrayerName);
    return format.replaceAll('{prayer}', translatedPrayer);
  }

  String _getTranslatedSoundLabel(BuildContext context, String soundKey) {
    switch (soundKey) {
      case 'default': return context.translate('sound_default');
      case 'silent': return context.translate('sound_silent');
      case 'makkah': return context.translate('sound_makkah');
      case 'madinah': return context.translate('sound_madinah');
      default: return soundKey;
    }
  }

  String _getTranslatedCalcMethodLabel(BuildContext context, String methodKey) {
    switch (methodKey) {
      case 'kemenag': return context.translate('method_kemenag');
      case 'singapore': return context.translate('method_singapore');
      case 'muslim_world_league': return context.translate('method_muslim_world_league');
      case 'egyptian': return context.translate('method_egyptian');
      case 'karachi': return context.translate('method_karachi');
      case 'umm_al_qura': return context.translate('method_umm_al_qura');
      case 'dubai': return context.translate('method_dubai');
      case 'kuwait': return context.translate('method_kuwait');
      case 'turkey': return context.translate('method_turkey');
      case 'tehran': return context.translate('method_tehran');
      default: return methodKey;
    }
  }

  String _getTranslatedMadhabLabel(BuildContext context, String madhabKey) {
    switch (madhabKey) {
      case 'syafii': return context.translate('madhab_syafii');
      case 'hanafi': return context.translate('madhab_hanafi');
      default: return madhabKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(context.translate('title_settings')),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── TAMPILAN ─────────────────────────────────────────
          _sectionHeader(context, context.translate('section_appearance')),
          _buildCard(context, [
            // Tema
            _buildTileLeading(context, 
              icon: Icons.dark_mode_rounded,
              iconColor: const Color(0xFF6C63FF),
              title: context.translate('tile_theme'),
              subtitle: Theme.of(context).brightness == Brightness.dark 
                  ? context.translate('theme_dark') 
                  : context.translate('theme_light'),
              trailing: Switch(
                value: Theme.of(context).brightness == Brightness.dark,
                activeThumbColor: AppTheme.primaryGreen,
                onChanged: (val) => settings.setThemeMode(
                  val ? ThemeMode.dark : ThemeMode.light,
                ),
              ),
            ),
            _divider(context),
            // Ukuran Font
            _buildTileExpanded(context, 
              icon: Icons.text_fields_rounded,
              iconColor: const Color(0xFF00BCD4),
              title: context.translate('tile_font_size'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('A', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text('A', style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text('A', style: TextStyle(fontSize: 24, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                    Slider(
                      value: settings.fontSize,
                      min: 0.85,
                      max: 1.2,
                      divisions: 2,
                      activeColor: AppTheme.primaryGreen,
                      inactiveColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      onChanged: settings.setFontSize,
                    ),
                    Center(
                      child: Text(
                        _getTranslatedFontSizeLabel(context, settings.fontSizeLabel),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _divider(context),
            // Bahasa
            _buildTileLeading(context, 
              icon: Icons.language_rounded,
              iconColor: const Color(0xFF4CAF50),
              title: context.translate('tile_language'),
              subtitle: settings.language == 'id' ? 'Bahasa Indonesia' : 'English',
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => _showLanguagePicker(context, settings),
            ),
            _divider(context),
            // Desain Mushaf
            _buildTileLeading(context, 
              icon: Icons.menu_book_rounded,
              iconColor: const Color(0xFFE91E63),
              title: context.translate('tile_quran_script'),
              subtitle: settings.quranScript == 'uthmani'
                  ? context.translate('quran_script_uthmani')
                  : context.translate('quran_script_indonesian'),
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => _showQuranScriptPicker(context, settings),
            ),
          ]),

          // ── NOTIFIKASI ───────────────────────────────────────
          _sectionHeader(context, context.translate('section_notifications')),
          _buildCard(context, [
            // Pengingat harian
            _buildTileLeading(context, 
              icon: Icons.alarm_rounded,
              iconColor: const Color(0xFFFF9800),
              title: context.translate('tile_reminder'),
              subtitle: settings.reminderEnabled
                  ? '${context.translate('status_active')} — ${settings.reminderTimeLabel}'
                  : context.translate('status_inactive'),
              trailing: Switch(
                value: settings.reminderEnabled,
                activeThumbColor: AppTheme.primaryGreen,
                onChanged: settings.setReminderEnabled,
              ),
            ),
            if (settings.reminderEnabled) ...[
              _divider(context),
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(56, 0, 16, 0),
                title: Text(context.translate('tile_reminder_time'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                subtitle: Text(settings.reminderTimeLabel,
                    style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600)),
                trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: settings.reminderHour,
                      minute: settings.reminderMinute,
                    ),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.dark(primary: AppTheme.primaryGreen),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    settings.setReminderTime(picked.hour, picked.minute);
                  }
                },
              ),
            ],
            _divider(context),
            // Update Grup
            _buildTileLeading(context, 
              icon: Icons.group_rounded,
              iconColor: AppTheme.primaryGreen,
              title: context.translate('tile_group_notif'),
              subtitle: context.translate('subtitle_group_notif'),
              trailing: Switch(
                value: settings.groupNotifEnabled,
                activeThumbColor: AppTheme.primaryGreen,
                onChanged: settings.setGroupNotif,
              ),
            ),
          ]),

          // ── SHALAT & AZAN ────────────────────────────────────
          _sectionHeader(context, context.translate('section_prayer_azan')),
          _buildCard(context, [
            // Master Azan Toggle
            _buildTileLeading(context, 
              icon: Icons.mosque_rounded,
              iconColor: const Color(0xFF00BCD4),
              title: context.translate('tile_azan_notif'),
              subtitle: _azanEnabled ? context.translate('status_active') : context.translate('status_inactive'),
              trailing: Switch(
                value: _azanEnabled,
                activeThumbColor: AppTheme.primaryGreen,
                onChanged: (val) async {
                  await AzanNotificationService.setAzanEnabled(val);
                  setState(() => _azanEnabled = val);
                },
              ),
            ),
            if (_azanEnabled) ...[
              _divider(context),
              // Per-prayer toggles
              ..._azanToggles.entries.map((entry) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      child: Row(
                        children: [
                          const SizedBox(width: 40),
                          Expanded(
                            child: Text(
                              _formatAzanTileTitle(context, entry.key),
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                          Switch(
                            value: entry.value,
                            activeThumbColor: AppTheme.primaryGreen,
                            onChanged: (val) async {
                              await AzanNotificationService.setAzanToggle(entry.key, val);
                              setState(() {
                                _azanToggles[entry.key] = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
              _divider(context),
              // Sound selection
              _buildTileLeading(context, 
                icon: Icons.volume_up_rounded,
                iconColor: const Color(0xFFFF9800),
                title: context.translate('tile_azan_sound'),
                subtitle: _getTranslatedSoundLabel(context, _azanSound),
                trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                onTap: () => _showAzanSoundPicker(context),
              ),
            ],
            _divider(context),
            // Calculation method
            _buildTileLeading(context, 
              icon: Icons.calculate_rounded,
              iconColor: const Color(0xFF6C63FF),
              title: context.translate('tile_calc_method'),
              subtitle: _getTranslatedCalcMethodLabel(context, _calcMethod),
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => _showCalcMethodPicker(context),
            ),
            _divider(context),
            // Madhab
            _buildTileLeading(context, 
              icon: Icons.school_rounded,
              iconColor: const Color(0xFF4CAF50),
              title: context.translate('tile_madhab'),
              subtitle: _getTranslatedMadhabLabel(context, _madhab),
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => _showMadhabPicker(context),
            ),
          ]),

          // ── TARGET ───────────────────────────────────────────
          _sectionHeader(context, context.translate('section_reading_target')),
          _buildCard(context, [
            _buildTileExpanded(context, 
              icon: Icons.flag_rounded,
              iconColor: const Color(0xFF4CAF50),
              title: context.translate('tile_daily_target'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(56, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.translate('target_daily_target_juz').replaceAll('{target}', settings.dailyTargetJuzLabel),
                      style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? AppTheme.primaryGreen.withOpacity(0.3)
                              : AppTheme.primaryGreen.withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: settings.dailyTargetJuz,
                          isExpanded: true,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primaryGreen),
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          items: [
                            DropdownMenuItem(value: 0.1, child: Text(context.translate('target_1_10'))),
                            DropdownMenuItem(value: 0.125, child: Text(context.translate('target_1_8'))),
                            DropdownMenuItem(value: 0.25, child: Text(context.translate('target_1_4'))),
                            DropdownMenuItem(value: 0.5, child: Text(context.translate('target_1_2'))),
                            DropdownMenuItem(value: 0.75, child: Text(context.translate('target_3_4'))),
                            DropdownMenuItem(value: 1.0, child: Text(context.translate('target_1'))),
                            DropdownMenuItem(value: 2.0, child: Text(context.translate('target_2'))),
                            DropdownMenuItem(value: 3.0, child: Text(context.translate('target_3'))),
                            DropdownMenuItem(value: 4.0, child: Text(context.translate('target_4'))),
                            DropdownMenuItem(value: 5.0, child: Text(context.translate('target_5'))),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              settings.setDailyTarget(val);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]),

          // ── TENTANG ──────────────────────────────────────────
          _sectionHeader(context, context.translate('section_about')),
          _buildCard(context, [
            _buildTileLeading(context, 
              icon: Icons.info_outline_rounded,
              iconColor: const Color(0xFF2196F3),
              title: context.translate('tile_about_app'),
              subtitle: 'Khataman Quran v$_appVersion',
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => _showAboutDialog(context),
            ),
            _divider(context),
            _buildTileLeading(context, 
              icon: Icons.privacy_tip_outlined,
              iconColor: const Color(0xFF9C27B0),
              title: context.translate('tile_privacy_policy'),
              subtitle: context.translate('subtitle_privacy_policy'),
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => _showPrivacyPolicyDialog(context),
            ),
            _divider(context),
            _buildTileLeading(context, 
              icon: Icons.history_rounded,
              iconColor: const Color(0xFFE91E63),
              title: context.translate('tile_changelog'),
              subtitle: context.translate('subtitle_changelog'),
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => _showChangelogDialog(context),
            ),
          ]),

          // ── AKUN ────────────────────────────────────────────
          _sectionHeader(context, context.translate('section_account')),
          _buildCard(context, [
            _buildTileLeading(context, 
              icon: Icons.delete_forever_rounded,
              iconColor: Colors.redAccent,
              title: context.translate('tile_delete_account'),
              subtitle: context.translate('subtitle_delete_account'),
              titleColor: Colors.redAccent,
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.redAccent),
              onTap: () => _confirmDeleteAccount(context),
            ),
          ]),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'Khataman Quran • v$_appVersion\n${context.translate('footer_made_with')}',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.6),
            ),
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppTheme.primaryGreen,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? AppTheme.primaryGreen.withOpacity(0.3) 
              : AppTheme.primaryGreen.withOpacity(0.2),
        ),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      color: isDark 
          ? AppTheme.primaryGreen.withOpacity(0.15) 
          : AppTheme.primaryGreen.withOpacity(0.12), 
      height: 1, 
      indent: 56,
    );
  }

  Widget _buildTileLeading(BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: TextStyle(color: titleColor ?? Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12))
          : null,
      trailing: trailing,
    );
  }

  Widget _buildTileExpanded(BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          title: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        child,
      ],
    );
  }
  void _showQuranScriptPicker(BuildContext context, SettingsProvider settings) {
    String selected = settings.quranScript;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.menu_book_rounded, color: Color(0xFFE91E63)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.translate('dialog_choose_quran_script'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: Text(context.translate('quran_script_uthmani'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                  value: 'uthmani',
                  groupValue: selected,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => selected = val);
                  },
                ),
                RadioListTile<String>(
                  title: Text(context.translate('quran_script_indonesian'), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                  value: 'indonesian',
                  groupValue: selected,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => selected = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.translate('btn_cancel'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await settings.setQuranScript(selected);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                child: Text(context.translate('btn_save'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, SettingsProvider settings) {
    String selected = settings.language;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.language_rounded, color: Color(0xFF4CAF50)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.translate('dialog_choose_language'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: Text('Bahasa Indonesia', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                  value: 'id',
                  groupValue: selected,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => selected = val);
                  },
                ),
                RadioListTile<String>(
                  title: Text('English', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                  value: 'en',
                  groupValue: selected,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => selected = val);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.translate('btn_cancel'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await settings.setLanguage(selected);
                  WidgetUpdateService.updatePrayerWidget();
                  WidgetUpdateService.updateKhatamanWidget();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                child: Text(context.translate('btn_save'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }
  void _showAzanSoundPicker(BuildContext context) {
    String selected = _azanSound;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.volume_up_rounded, color: Color(0xFFFF9800)),
                const SizedBox(width: 8),
                Text(context.translate('tile_azan_sound'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: AzanNotificationService.azanSoundOptions.entries.map((e) {
                return RadioListTile<String>(
                  title: Text(_getTranslatedSoundLabel(context, e.key), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                  value: e.key,
                  groupValue: selected,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => selected = val);
                  },
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.translate('btn_cancel'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await AzanNotificationService.setAzanSound(selected);
                  setState(() => _azanSound = selected);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                child: Text(context.translate('btn_save'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCalcMethodPicker(BuildContext context) {
    String selected = _calcMethod;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.calculate_rounded, color: Color(0xFF6C63FF)),
                const SizedBox(width: 8),
                Text(context.translate('tile_calc_method'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: ListView(
                shrinkWrap: true,
                children: PrayerTimeService.calcMethodOptions.entries.map((e) {
                  return RadioListTile<String>(
                    title: Text(_getTranslatedCalcMethodLabel(context, e.key), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                    value: e.key,
                    groupValue: selected,
                    activeColor: AppTheme.primaryGreen,
                    onChanged: (val) {
                      if (val != null) setStateDialog(() => selected = val);
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.translate('btn_cancel'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await PrayerTimeService.setCalcMethod(selected);
                  setState(() => _calcMethod = selected);
                  WidgetUpdateService.updatePrayerWidget();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                child: Text(context.translate('btn_save'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMadhabPicker(BuildContext context) {
    String selected = _madhab;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.school_rounded, color: Color(0xFF4CAF50)),
                const SizedBox(width: 8),
                Text(context.translate('tile_madhab'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: PrayerTimeService.madhabOptions.entries.map((e) {
                return RadioListTile<String>(
                  title: Text(_getTranslatedMadhabLabel(context, e.key), style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                  subtitle: Text(
                    e.key == 'syafii'
                        ? context.translate('madhab_desc_syafii')
                        : context.translate('madhab_desc_hanafi'),
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  value: e.key,
                  groupValue: selected,
                  activeColor: AppTheme.primaryGreen,
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => selected = val);
                  },
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.translate('btn_cancel'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              ElevatedButton(
                onPressed: () async {
                  await PrayerTimeService.setMadhab(selected);
                  setState(() => _madhab = selected);
                  WidgetUpdateService.updatePrayerWidget();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen),
                child: Text(context.translate('btn_save'), style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(context.translate('about_title'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${context.translate('about_version')}: $_appVersion', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(
              context.translate('about_desc'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(context.translate('about_tech_stack'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('• Flutter (Dart)\n• Supabase (PostgreSQL)\n• Google OAuth',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.6)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.translate('btn_close'), style: const TextStyle(color: AppTheme.primaryGreen)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.privacy_tip_rounded, color: Color(0xFF9C27B0), size: 28),
            const SizedBox(width: 8),
            Text(context.translate('tile_privacy_policy'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.translate('policy_intro'),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, height: 1.5, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _policySection(context, context.translate('policy_1_title'), 
                  context.translate('policy_1_body')),
                _policySection(context, context.translate('policy_2_title'), 
                  context.translate('policy_2_body')),
                _policySection(context, context.translate('policy_3_title'), 
                  context.translate('policy_3_body')),
                _policySection(context, context.translate('policy_4_title'), 
                  context.translate('policy_4_body')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.translate('policy_dialog_close'), style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _policySection(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _showChangelogDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.history_rounded, color: Color(0xFFE91E63), size: 28),
            const SizedBox(width: 8),
            Text(context.translate('changelog_title'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _changelogVersion(
                  context,
                  version: context.translate('changelog_v1_13_0_header'),
                  changes: [
                    context.translate('changelog_v1_13_0_1'),
                    context.translate('changelog_v1_13_0_2'),
                    context.translate('changelog_v1_13_0_3'),
                    context.translate('changelog_v1_13_0_4'),
                    context.translate('changelog_v1_13_0_5'),
                  ],
                ),
                const SizedBox(height: 16),
                _changelogVersion(
                  context,
                  version: context.translate('changelog_v1_1_0_header'),
                  changes: [
                    context.translate('changelog_v1_1_0_1'),
                    context.translate('changelog_v1_1_0_2'),
                    context.translate('changelog_v1_1_0_3'),
                    context.translate('changelog_v1_1_0_4'),
                    context.translate('changelog_v1_1_0_5'),
                  ],
                ),
                const SizedBox(height: 16),
                _changelogVersion(
                  context,
                  version: context.translate('changelog_v1_0_0_header'),
                  changes: [
                    context.translate('changelog_v1_0_0_1'),
                    context.translate('changelog_v1_0_0_2'),
                    context.translate('changelog_v1_0_0_3'),
                    context.translate('changelog_v1_0_0_4'),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.translate('btn_close'), style: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _changelogVersion(BuildContext context, {required String version, required List<String> changes}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            version,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primaryGreen),
          ),
        ),
        const SizedBox(height: 8),
        ...changes.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Text(
                      c,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  void _showLoadingDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
      ),
    );
  }

  Future<String?> _showChooseNewAdminDialog(
      BuildContext context, String groupName, List<Map<String, dynamic>> members) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        String? selectedUserId;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.stars_rounded, color: AppTheme.accentGold, size: 28),
                      SizedBox(width: 8),
                      Text('Pilih Admin Baru', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.translate('dialog_body_new_admin').replaceAll('{groupName}', groupName),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 280,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: members.length,
                  itemBuilder: (context, idx) {
                    final m = members[idx];
                    final user = m['users'] as Map<String, dynamic>? ?? {};
                    final uid = user['id_user'] as String? ?? m['user_id'] as String;
                    final username = user['username'] as String? ?? 'Anggota';
                    final email = user['email'] as String? ?? '';
                    final avatarUrl = user['avatar_url'] as String?;
                    final isSelected = selectedUserId == uid;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryGreen.withOpacity(0.08)
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryGreen
                              : Theme.of(context).dividerColor.withOpacity(0.2),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        onTap: () {
                          setStateDialog(() {
                            selectedUserId = uid;
                          });
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: CircleAvatar(
                          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                          onBackgroundImageError: (_, __) {},
                          child: avatarUrl == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(
                          username,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        subtitle: email.isNotEmpty
                            ? Text(
                                email,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                        trailing: Radio<String>(
                          value: uid,
                          groupValue: selectedUserId,
                          activeColor: AppTheme.primaryGreen,
                          onChanged: (val) {
                            setStateDialog(() {
                              selectedUserId = val;
                            });
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(context.translate('btn_cancel'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: selectedUserId == null
                            ? null
                            : () => Navigator.pop(ctx, selectedUserId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        child: Text(context.translate('btn_confirm_continue')),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    final supabase = Supabase.instance.client;
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        bool isValid = false;
        final requiredText = context.translate('delete_verify_text');

        return StatefulBuilder(
          builder: (statefulCtx, setStateDialog) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 8),
                  Text(context.translate('delete_confirm_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.translate('delete_confirm_body'),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.translate('delete_confirm_type_sentence'),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    requiredText,
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.2),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: textController,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: context.translate('delete_verify_hint'),
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (val) {
                      setStateDialog(() {
                        isValid = val.trim() == requiredText;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      // Tombol Batal (Secondary Button)
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          style: TextButton.styleFrom(
                            backgroundColor: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withOpacity(0.08)
                                : Colors.grey.shade100,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            context.translate('btn_cancel'),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Tombol Ya, Hapus (Primary Destructive Button)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isValid
                              ? () async {
                                  Navigator.pop(dialogCtx); // Close warning dialog
                                  _showLoadingDialog(context); // Show loading dialog
                                  
                                  try {
                                    final userId = supabase.auth.currentUser?.id;
                                    if (userId == null) {
                                      Navigator.pop(context); // Dismiss loading dialog
                                      return;
                                    }

                                    // 1. Dapatkan semua grup di mana user adalah CREATOR/ADMIN
                                    final myGroupsAsAdmin = await supabase
                                        .from('groups')
                                        .select('id_group, nama_grup')
                                        .eq('creator_id', userId);

                                    final adminGroupsList = myGroupsAsAdmin as List;
                                    
                                    // Hide loading dialog before showing chooser dialogs
                                    Navigator.pop(context);

                                    Map<String, String> selectedNewAdmins = {};

                                    for (var group in adminGroupsList) {
                                      final String groupId = group['id_group'].toString();
                                      final String groupName = group['nama_grup'] ?? 'Grup';

                                      // Query anggota APPROVED lainnya
                                      final otherMembersRes = await supabase
                                          .from('group_members')
                                          .select('user_id, users(id_user, username, email, avatar_url)')
                                          .eq('group_id', groupId)
                                          .eq('approval_status', 'APPROVED')
                                          .neq('user_id', userId);

                                      final otherMembers = otherMembersRes as List;

                                      if (otherMembers.isNotEmpty) {
                                        if (context.mounted) {
                                          final selectedAdminId = await _showChooseNewAdminDialog(
                                            context,
                                            groupName,
                                            List<Map<String, dynamic>>.from(otherMembers),
                                          );

                                          if (selectedAdminId == null) {
                                            // User cancelled choice, abort entire process!
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text(context.translate('msg_delete_cancelled')),
                                                  backgroundColor: Colors.redAccent,
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          selectedNewAdmins[groupId] = selectedAdminId;
                                        }
                                      }
                                    }

                                    // Show loading dialog again for final execution
                                    if (context.mounted) {
                                      _showLoadingDialog(context);
                                    }

                                    // 2. Terapkan pemindahan admin
                                    for (var entry in selectedNewAdmins.entries) {
                                      await supabase
                                          .from('groups')
                                          .update({'creator_id': entry.value})
                                          .eq('id_group', entry.key);
                                    }

                                    // 3. Hapus grup-grup kosong di mana user adalah creator dan tidak ada anggota lain
                                    for (var group in adminGroupsList) {
                                      final String groupId = group['id_group'].toString();
                                      if (!selectedNewAdmins.containsKey(groupId)) {
                                        await supabase.from('groups').delete().eq('id_group', groupId);
                                      }
                                    }

                                    // Query username first before deleting user profile
                                    String? myUsername;
                                    try {
                                      final uRes = await supabase.from('users').select('username').eq('id_user', userId).maybeSingle();
                                      if (uRes != null) {
                                        myUsername = uRes['username'] as String?;
                                      }
                                    } catch (_) {}

                                    // 4. Hapus dari keanggotaan grup (`group_members`)
                                    await supabase.from('group_members').delete().eq('user_id', userId);

                                    // 5. Tangani Slot Membaca Grup (slot_khataman)
                                    // A. Selesai 100% -> Dipertahankan sebagai snapshot (set user_id ke null)
                                    await supabase
                                        .from('slot_khataman')
                                        .update({
                                          'user_id': null,
                                          'username_sebelumnya': myUsername,
                                        })
                                        .eq('user_id', userId)
                                        .eq('status_checklist', true);

                                    // B. Belum selesai 100% -> Reset & Lepas ke grup (status = false, input = 0, user = null)
                                    await supabase
                                        .from('slot_khataman')
                                        .update({
                                          'user_id': null,
                                          'ayat_terakhir_input': 0,
                                          'status_checklist': false,
                                          'username_sebelumnya': myUsername,
                                        })
                                        .eq('user_id', userId)
                                        .eq('status_checklist', false);

                                    // 6. Hapus data pribadi
                                    await supabase.from('notifications').delete().eq('user_id', userId);
                                    await supabase.from('riwayat_personal').delete().eq('user_id', userId);
                                    await supabase.from('khataman_mandiri').delete().eq('user_id', userId);

                                    // 7. Hapus user profile
                                    await supabase.from('users').delete().eq('id_user', userId);

                                    // 7.5 Hapus dari auth.users menggunakan RPC (jika sudah dikonfigurasi di Supabase)
                                    try {
                                      await supabase.rpc('delete_user');
                                    } catch (rpcError) {
                                      debugPrint('Info: RPC delete_user tidak ditemukan atau gagal: $rpcError. Melanjutkan logout.');
                                    }

                                    // 8. Bersihkan SharedPreferences lokal
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.clear();

                                    // 9. Sign out Supabase auth
                                    await supabase.auth.signOut();

                                    // Dismiss loading dialog
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      Navigator.of(context).popUntil((route) => route.isFirst);
                                    }
                                  } catch (e) {
                                    debugPrint('Error deleting account: $e');
                                    // In case of error, make sure loading dialog is closed
                                    if (context.mounted) {
                                      Navigator.pop(context); // Close loading dialog
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('${context.translate('msg_delete_failed')}: $e'), backgroundColor: Colors.redAccent),
                                      );
                                    }
                                  }
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.redAccent.withOpacity(0.3),
                            disabledForegroundColor: Colors.white.withOpacity(0.6),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(context.translate('delete_btn_yes'), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}