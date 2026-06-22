import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/localization.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _usernameController = TextEditingController();
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await _supabase
          .from('users')
          .select()
          .eq('id_user', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _profile = data;
          _usernameController.text = data['username'] ?? '';
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveUsername() async {
    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) {
      _showSnackbar(context.translate('profile_err_empty_username'), isError: true);
      return;
    }
    if (newUsername.length < 3) {
      _showSnackbar(context.translate('profile_err_min_char'), isError: true);
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(newUsername)) {
      _showSnackbar(context.translate('profile_err_invalid_char'), isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _supabase
          .from('users')
          .update({'username': newUsername})
          .eq('id_user', _supabase.auth.currentUser!.id);

      setState(() {
        _profile = {...?_profile, 'username': newUsername};
        _isEditing = false;
        _isSaving = false;
      });
      _showSnackbar(context.translate('profile_success_username_changed'));
    } catch (e) {
      setState(() => _isSaving = false);
      if (e.toString().contains('unique') || e.toString().contains('duplicate')) {
        _showSnackbar(context.translate('profile_err_username_taken'), isError: true);
      } else {
        _showSnackbar(context.translate('mandiri_save_failed').replaceFirst('{error}', e.toString()), isError: true);
      }
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : AppTheme.primaryGreen,
    ));
  }

  void _confirmLogout(AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(context.translate('profile_confirm_logout_title'), style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          context.translate('profile_confirm_logout_body'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.translate('btn_cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Tutup dialog
              Navigator.of(context).popUntil((route) => route.isFirst); // Kembali ke root
              auth.signOut();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(context.translate('profile_confirm_logout_yes')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<SettingsProvider>(context); // Listen to settings changes
    final authProvider = Provider.of<AuthProvider>(context);
    final user = _supabase.auth.currentUser;
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
    final email = user?.email ?? '';
    final username = _profile?['username'] ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(context.translate('profile_title')),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
              child: Column(
                children: [
                  const SizedBox(height: 12),

                  // ── Avatar ──────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primaryGreen, width: 3),
                    ),
                    child: CircleAvatar(
                      radius: 54,
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                      onBackgroundImageError: (_, __) {},
                      child: avatarUrl == null
                          ? Icon(Icons.person_rounded, size: 50, color: Theme.of(context).colorScheme.onSurfaceVariant)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Display name from Google ─────────────────
                  Text(
                    user?.userMetadata?['full_name'] as String? ?? context.translate('profile_fallback_username'),
                    style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),

                  // ── Username Card ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark 
                            ? AppTheme.primaryGreen.withOpacity(0.3) 
                            : AppTheme.primaryGreen.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text('Username', style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600,
                                )),
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: context.translate('profile_username_rules'),
                                  textStyle: const TextStyle(color: Colors.white, fontSize: 11, height: 1.4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[850],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  triggerMode: TooltipTriggerMode.tap,
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    size: 14,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (!_isEditing)
                              GestureDetector(
                                onTap: () => setState(() => _isEditing = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_rounded, size: 14, color: AppTheme.primaryGreen),
                                      const SizedBox(width: 4),
                                      Text(context.translate('profile_btn_edit'), style: const TextStyle(color: AppTheme.primaryGreen, fontSize: 13, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_isEditing) ...[
                          TextField(
                            controller: _usernameController,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                            decoration: InputDecoration(
                              hintText: context.translate('profile_hint_new_username'),
                              prefixText: '@',
                              prefixStyle: const TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600),
                            ),
                            autofocus: true,
                          ),
                          const SizedBox(height: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildGuidelineRow(context, context.translate('profile_rule_min_char')),
                              const SizedBox(height: 4),
                              _buildGuidelineRow(context, context.translate('profile_rule_valid_char')),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isSaving
                                      ? null
                                      : () {
                                          _usernameController.text = _profile?['username'] ?? '';
                                          setState(() => _isEditing = false);
                                        },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                                    side: BorderSide(
                                      color: isDark 
                                          ? AppTheme.primaryGreen.withOpacity(0.5) 
                                          : AppTheme.primaryGreen.withOpacity(0.4),
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  child: Text(context.translate('btn_cancel'), style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : _saveUsername,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDark ? const Color(0xFF1B8047) : AppTheme.primaryGreen,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    minimumSize: const Size.fromHeight(48),
                                  ),
                                  child: _isSaving
                                      ? const SizedBox(
                                          width: 20, height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text(context.translate('btn_save'), style: const TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              const Text('@', style: TextStyle(color: AppTheme.primaryGreen, fontSize: 18, fontWeight: FontWeight.w600)),
                              Expanded(
                                child: Text(
                                  username,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Info Card ────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark 
                            ? AppTheme.primaryGreen.withOpacity(0.3) 
                            : AppTheme.primaryGreen.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(Icons.email_rounded, context.translate('profile_tile_email'), email),
                        Divider(
                          color: isDark 
                              ? AppTheme.primaryGreen.withOpacity(0.15) 
                              : AppTheme.primaryGreen.withOpacity(0.12),
                          height: 24,
                          indent: 38,
                        ),
                        _buildInfoRow(
                          Icons.login_rounded,
                          context.translate('profile_tile_login_with'),
                          'Google',
                          trailing: Image.network(
                            'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                            width: 20, height: 20,
                            errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata_rounded, color: Colors.red),
                          ),
                        ),
                        Divider(
                          color: isDark 
                              ? AppTheme.primaryGreen.withOpacity(0.15) 
                              : AppTheme.primaryGreen.withOpacity(0.12),
                          height: 24,
                          indent: 38,
                        ),
                        _buildInfoRow(
                          Icons.calendar_today_rounded,
                          context.translate('profile_tile_joined_since'),
                          _profile?['created_at'] != null
                              ? _formatDate(context, _profile!['created_at'])
                              : '-',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Logout Button ─────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmLogout(authProvider),
                      icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                      label: Text(context.translate('profile_btn_logout'), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 1.5),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Widget? trailing}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
            Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
        if (trailing != null) ...[
          const Spacer(),
          trailing,
        ],
      ],
    );
  }

  String _formatDate(BuildContext context, String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final monthKeys = [
        'month_jan_short',
        'month_feb_short',
        'month_mar_short',
        'month_apr_short',
        'month_may_short',
        'month_jun_short',
        'month_jul_short',
        'month_aug_short',
        'month_sep_short',
        'month_oct_short',
        'month_nov_short',
        'month_dec_short',
      ];
      final monthName = context.translate(monthKeys[date.month - 1]);
      return '${date.day} $monthName ${date.year}';
    } catch (_) {
      return isoDate;
    }
  }

  Widget _buildGuidelineRow(BuildContext context, String text) {
    return Row(
      children: [
        const Icon(Icons.check_circle_outline_rounded, size: 12, color: AppTheme.primaryGreen),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
          ),
        ),
      ],
    );
  }
}