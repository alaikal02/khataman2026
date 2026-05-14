import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'settings_screen.dart';

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
      _showSnackbar('Username tidak boleh kosong', isError: true);
      return;
    }
    if (newUsername.length < 3) {
      _showSnackbar('Username minimal 3 karakter', isError: true);
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(newUsername)) {
      _showSnackbar('Username hanya boleh huruf, angka, dan underscore (_)', isError: true);
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
      _showSnackbar('Username berhasil diubah!');
    } catch (e) {
      setState(() => _isSaving = false);
      if (e.toString().contains('unique') || e.toString().contains('duplicate')) {
        _showSnackbar('Username sudah dipakai orang lain, coba yang lain', isError: true);
      } else {
        _showSnackbar('Gagal menyimpan: $e', isError: true);
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
        title: Text('Keluar?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Anda akan keluar dari akun ini.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              auth.signOut();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text('Ya, Keluar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = _supabase.auth.currentUser;
    final avatarUrl = user?.userMetadata?['avatar_url'] as String?;
    final email = user?.email ?? '';
    final username = _profile?['username'] ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Profil Saya'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
          : SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  SizedBox(height: 12),

                  // ── Avatar ──────────────────────────────────
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primaryGreen, width: 3),
                        ),
                        child: CircleAvatar(
                          radius: 54,
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null
                              ? Icon(Icons.person_rounded, size: 50, color: Theme.of(context).colorScheme.onSurfaceVariant)
                              : null,
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // ── Display name from Google ─────────────────
                  Text(
                    user?.userMetadata?['full_name'] as String? ?? 'Pengguna',
                    style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    email,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  SizedBox(height: 32),

                  // ── Username Card ─────────────────────────────
                  Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Username', style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600,
                            )),
                            if (!_isEditing)
                              GestureDetector(
                                onTap: () => setState(() => _isEditing = true),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_rounded, size: 14, color: AppTheme.primaryGreen),
                                      SizedBox(width: 4),
                                      Text('Ubah', style: TextStyle(color: AppTheme.primaryGreen, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 12),
                        if (_isEditing) ...[
                          TextField(
                            controller: _usernameController,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                            decoration: InputDecoration(
                              hintText: 'Masukkan username baru',
                              prefixText: '@',
                              prefixStyle: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600),
                              helperText: 'Hanya huruf, angka, dan underscore. Min. 3 karakter.',
                              helperStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                            ),
                            autofocus: true,
                          ),
                          SizedBox(height: 14),
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
                                    side: BorderSide(color: Theme.of(context).dividerColor),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: EdgeInsets.symmetric(vertical: 13),
                                  ),
                                  child: Text('Batal', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isSaving ? null : _saveUsername,
                                  style: ElevatedButton.styleFrom(
                                    padding: EdgeInsets.symmetric(vertical: 13),
                                  ),
                                  child: _isSaving
                                      ? SizedBox(
                                          width: 18, height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text('Simpan'),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Text('@', style: TextStyle(color: AppTheme.primaryGreen, fontSize: 18, fontWeight: FontWeight.w600)),
                              Text(
                                username,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(height: 16),

                  // ── Info Card ────────────────────────────────
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(Icons.email_rounded, 'Email', email),
                        Divider(color: Theme.of(context).dividerColor, height: 24),
                        _buildInfoRow(
                          Icons.login_rounded,
                          'Login dengan',
                          'Google',
                          trailing: Image.network(
                            'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                            width: 20, height: 20,
                            errorBuilder: (_, __, ___) => Icon(Icons.g_mobiledata_rounded, color: Colors.red),
                          ),
                        ),
                        Divider(color: Theme.of(context).dividerColor, height: 24),
                        _buildInfoRow(
                          Icons.calendar_today_rounded,
                          'Bergabung sejak',
                          _profile?['created_at'] != null
                              ? _formatDate(_profile!['created_at'])
                              : '-',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 32),

                  // ── Logout Button ─────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmLogout(authProvider),
                      icon: Icon(Icons.logout_rounded, color: Colors.redAccent),
                      label: Text('Keluar dari Akun', style: TextStyle(color: Colors.redAccent)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.redAccent),
                        padding: EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Widget? trailing}) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        SizedBox(width: 12),
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

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'];
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return isoDate;
    }
  }
}