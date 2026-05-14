import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Pengaturan'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [

          // ── TAMPILAN ─────────────────────────────────────────
          _sectionHeader(context, 'Tampilan'),
          _buildCard(context, [
            // Tema
            _buildTileLeading(context, 
              icon: Icons.dark_mode_rounded,
              iconColor: const Color(0xFF6C63FF),
              title: 'Tema Aplikasi',
              subtitle: settings.themeMode == ThemeMode.dark ? 'Gelap' : 'Terang',
              trailing: Switch(
                value: settings.themeMode == ThemeMode.dark,
                activeColor: AppTheme.primaryGreen,
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
              title: 'Ukuran Teks',
              child: Padding(
                padding: EdgeInsets.fromLTRB(56, 0, 16, 12),
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
                        settings.fontSizeLabel,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ]),

          // ── NOTIFIKASI ───────────────────────────────────────
          _sectionHeader(context, 'Notifikasi'),
          _buildCard(context, [
            // Pengingat harian
            _buildTileLeading(context, 
              icon: Icons.alarm_rounded,
              iconColor: const Color(0xFFFF9800),
              title: 'Pengingat Khataman',
              subtitle: settings.reminderEnabled
                  ? 'Aktif — ${settings.reminderTimeLabel}'
                  : 'Nonaktif',
              trailing: Switch(
                value: settings.reminderEnabled,
                activeColor: AppTheme.primaryGreen,
                onChanged: settings.setReminderEnabled,
              ),
            ),
            if (settings.reminderEnabled) ...[
              _divider(context),
              ListTile(
                contentPadding: EdgeInsets.fromLTRB(56, 0, 16, 0),
                title: Text('Jam Pengingat', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
                subtitle: Text(settings.reminderTimeLabel,
                    style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600)),
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
              title: 'Notifikasi Update Grup',
              subtitle: 'Saat anggota klaim atau selesai Juz',
              trailing: Switch(
                value: settings.groupNotifEnabled,
                activeColor: AppTheme.primaryGreen,
                onChanged: settings.setGroupNotif,
              ),
            ),
          ]),

          // ── TARGET ───────────────────────────────────────────
          _sectionHeader(context, 'Target Membaca'),
          _buildCard(context, [
            _buildTileExpanded(context, 
              icon: Icons.flag_rounded,
              iconColor: const Color(0xFF4CAF50),
              title: 'Target Harian',
              child: Padding(
                padding: EdgeInsets.fromLTRB(56, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${settings.dailyTargetJuz} Juz per hari',
                      style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 4),
                    Slider(
                      value: settings.dailyTargetJuz.toDouble(),
                      min: 1,
                      max: 5,
                      divisions: 4,
                      activeColor: AppTheme.primaryGreen,
                      inactiveColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      label: '${settings.dailyTargetJuz} Juz',
                      onChanged: (val) => settings.setDailyTarget(val.round()),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('1 Juz', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                        Text('3 Juz', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                        Text('5 Juz', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ]),

          // ── TENTANG ──────────────────────────────────────────
          _sectionHeader(context, 'Tentang'),
          _buildCard(context, [
            _buildTileLeading(context, 
              icon: Icons.info_outline_rounded,
              iconColor: const Color(0xFF2196F3),
              title: 'Tentang Aplikasi',
              subtitle: 'Khataman Quran v1.0.0',
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onTap: () => _showAboutDialog(context),
            ),
            _divider(context),
            _buildTileLeading(context, 
              icon: Icons.privacy_tip_outlined,
              iconColor: const Color(0xFF9C27B0),
              title: 'Kebijakan Privasi',
              subtitle: 'Cara kami melindungi data Anda',
              trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ]),

          // ── AKUN ────────────────────────────────────────────
          _sectionHeader(context, 'Akun'),
          _buildCard(context, [
            _buildTileLeading(context, 
              icon: Icons.delete_forever_rounded,
              iconColor: Colors.redAccent,
              title: 'Hapus Akun',
              subtitle: 'Hapus akun dan semua data Anda secara permanen',
              titleColor: Colors.redAccent,
              trailing: Icon(Icons.chevron_right_rounded, color: Colors.redAccent),
              onTap: () => _confirmDeleteAccount(context),
            ),
          ]),

          SizedBox(height: 32),
          Center(
            child: Text(
              'Khataman Quran • v1.0.0\nDibuat dengan ❤️ untuk umat',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.6),
            ),
          ),
          SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 20, 0, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: AppTheme.primaryGreen,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, List<Widget> children) {
    return Container(
      margin: EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(BuildContext context) => Divider(color: Theme.of(context).dividerColor, height: 1, indent: 56);

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
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: EdgeInsets.all(8),
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
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: EdgeInsets.all(8),
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

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Tentang Khataman Quran', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versi: 1.0.0', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            SizedBox(height: 8),
            Text(
              'Aplikasi untuk melacak progres Khataman Al-Quran secara mandiri maupun bersama dalam grup.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
            ),
            SizedBox(height: 12),
            Text('Stack Teknologi:', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('• Flutter (Dart)\n• Supabase (PostgreSQL)\n• Google OAuth',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.6)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Tutup', style: TextStyle(color: AppTheme.primaryGreen)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context) {
    final supabase = Supabase.instance.client;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('⚠️ Hapus Akun?', style: TextStyle(color: Colors.redAccent)),
        content: Text(
          'Seluruh data Anda (progres khataman, keanggotaan grup) akan dihapus secara PERMANEN dan tidak dapat dikembalikan.\n\nApakah Anda yakin?',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final userId = supabase.auth.currentUser?.id;
                if (userId != null) {
                  // Hapus data user dari tabel users (cascade akan hapus semua)
                  await supabase.from('users').delete().eq('id_user', userId);
                  await supabase.auth.signOut();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Gagal menghapus akun: $e'), backgroundColor: Colors.redAccent),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text('Ya, Hapus Permanen'),
          ),
        ],
      ),
    );
  }
}