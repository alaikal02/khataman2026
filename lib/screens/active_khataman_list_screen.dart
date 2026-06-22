import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:quran/quran.dart' as quran;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'mandiri_screen.dart';
import '../features/group/presentation/group_detail_screen.dart';
import '../providers/settings_provider.dart';
import '../utils/localization.dart';

class ActiveKhatamanListScreen extends StatefulWidget {
  const ActiveKhatamanListScreen({Key? key}) : super(key: key);

  static void invalidateCache() {
    _ActiveKhatamanListScreenState.invalidateCache();
  }

  @override
  State<ActiveKhatamanListScreen> createState() => _ActiveKhatamanListScreenState();
}

class _ActiveKhatamanListScreenState extends State<ActiveKhatamanListScreen> {
  static List<Map<String, dynamic>>? _cachedActivePrograms;
  static String? _cachedUserId;

  static void invalidateCache() {
    _cachedActivePrograms = null;
    _cachedUserId = null;
  }

  List<Map<String, dynamic>> _activePrograms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != _cachedUserId) {
      _cachedUserId = userId;
      _cachedActivePrograms = null;
    }

    _activePrograms = _cachedActivePrograms ?? [];
    _isLoading = _cachedActivePrograms == null;

    _loadActivePrograms();
  }

  Future<void> _loadActivePrograms() async {
    if (!mounted) return;
    if (_cachedActivePrograms == null) {
      setState(() {
        _isLoading = true;
      });
    }

    final programs = await _fetchActivePrograms();

    _cachedActivePrograms = programs;
    if (mounted) {
      setState(() {
        _activePrograms = _cachedActivePrograms!;
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchActivePrograms() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];

    List<Map<String, dynamic>> programs = [];

    // 1. Fetch Mandiri
    try {
      final mandiriRes = await Supabase.instance.client
          .from('khataman_mandiri')
          .select()
          .eq('user_id', userId);

      if (mandiriRes.isNotEmpty) {
        final completedCount = mandiriRes.where((p) => p['selesai'] == true).length;
        if (completedCount < 30) {
          double totalProgressSum = 0.0;
          DateTime latestUpdated = DateTime.fromMillisecondsSinceEpoch(0);
          
          for (var row in mandiriRes) {
            final updatedAtStr = row['updated_at'] as String?;
            if (updatedAtStr != null) {
              final parsedDate = DateTime.parse(updatedAtStr);
              if (parsedDate.isAfter(latestUpdated)) {
                latestUpdated = parsedDate;
              }
            }

            if (row['selesai'] == true) {
              totalProgressSum += 1.0;
            } else {
              final lastAyat = row['ayat_terakhir'] as int? ?? 0;
              if (lastAyat > 0) {
                final juzNum = row['nomor_juz'] as int;
                final surahsInJuz = quran.getSurahAndVersesFromJuz(juzNum);
                int totalAyatInJuz = 0;
                surahsInJuz.forEach((surah, bounds) {
                  totalAyatInJuz += (bounds[1] - bounds[0] + 1);
                });
                if (totalAyatInJuz > 0) {
                  double fraction = lastAyat / totalAyatInJuz;
                  totalProgressSum += fraction > 1.0 ? 1.0 : fraction;
                }
              }
            }
          }

          final progressPercent = (totalProgressSum / 30.0) * 100;
          programs.add({
            'type': 'MANDIRI',
            'title': 'Khataman Mandiri',
            'code': null,
            'progress': progressPercent,
            'updated_at': latestUpdated,
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching active mandiri: $e');
    }

    // 2. Fetch Active Group slots (fetch all user slots in active cycles to get correct latest updated_at)
    try {
      final slotsRes = await Supabase.instance.client
          .from('slot_khataman')
          .select('*, putaran_siklus!inner(*)')
          .eq('user_id', userId)
          .eq('putaran_siklus.status_aktif_selesai', 'AKTIF');

      final slotsList = slotsRes as List;
      if (slotsList.isNotEmpty) {
        // Group by group_id
        Map<String, List<Map<String, dynamic>>> slotsByGroup = {};
        for (var s in slotsList) {
          final putaran = s['putaran_siklus'] as Map<String, dynamic>;
          final groupId = putaran['group_id'] as String;
          slotsByGroup.putIfAbsent(groupId, () => []).add(s);
        }

        if (slotsByGroup.isNotEmpty) {
          final groupIds = slotsByGroup.keys.toList();
          final groupsRes = await Supabase.instance.client
              .from('groups')
              .select('*')
              .inFilter('id_group', groupIds);

          final groupsList = groupsRes as List;
          Map<String, Map<String, dynamic>> groupsMap = {
            for (var g in groupsList) g['id_group'] as String: g
          };

          final putaranIds = slotsList.map((s) => s['putaran_id'] as String).toSet().toList();
          final allSlotsRes = await Supabase.instance.client
              .from('slot_khataman')
              .select('putaran_id, status_checklist')
              .inFilter('putaran_id', putaranIds);

          final allSlotsList = allSlotsRes as List;
          
          Map<String, int> completedSlotsCount = {};
          for (var s in allSlotsList) {
            final pId = s['putaran_id'] as String;
            if (s['status_checklist'] == true) {
              completedSlotsCount[pId] = (completedSlotsCount[pId] ?? 0) + 1;
            }
          }

          for (var entry in slotsByGroup.entries) {
            final groupId = entry.key;
            final groupSlots = entry.value;
            final groupData = groupsMap[groupId];
            if (groupData == null) continue;

            DateTime latestUpdated = DateTime.fromMillisecondsSinceEpoch(0);
            for (var s in groupSlots) {
              final updatedAtStr = s['updated_at'] as String?;
              if (updatedAtStr != null) {
                final parsedDate = DateTime.parse(updatedAtStr);
                if (parsedDate.isAfter(latestUpdated)) {
                  latestUpdated = parsedDate;
                }
              }
            }

            final putaranId = groupSlots.first['putaran_id'] as String;
            final completedCount = completedSlotsCount[putaranId] ?? 0;
            final progressPercent = (completedCount / 30.0) * 100;

            programs.add({
              'type': 'GROUP',
              'title': groupData['nama_grup'] as String,
              'code': groupData['kode_gk_unik'] as String?,
              'progress': progressPercent,
              'updated_at': latestUpdated,
              'groupId': groupId,
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching active group slots: $e');
    }

    programs.sort((a, b) => (b['updated_at'] as DateTime).compareTo(a['updated_at'] as DateTime));
    return programs;
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<SettingsProvider>(context); // Listen to settings changes
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF161B22) : const Color(0xFFEEEEEE),
      appBar: AppBar(
        title: Text(context.translate('active_list_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: isDark ? AppTheme.darkBgGradient : AppTheme.lightBgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadActivePrograms,
            color: AppTheme.primaryGreen,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryGreen))
                : _activePrograms.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: _activePrograms.length,
                        itemBuilder: (context, index) {
                          return _buildShortcutCard(context, _activePrograms[index]);
                        },
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.2),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : AppTheme.primaryGreen.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  size: 64,
                  color: isDark ? Colors.white54 : AppTheme.darkGreen.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.translate('active_list_empty_title'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  context.translate('active_list_empty_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutCard(BuildContext context, Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGroup = item['type'] == 'GROUP';
    final progress = item['progress'] as double;
    final progressText = '${progress.toStringAsFixed(1)}%';

    return GestureDetector(
      onTap: () {
        if (isGroup) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GroupDetailScreen(groupId: item['groupId'] as String),
            ),
          ).then((_) => _loadActivePrograms());
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MandiriScreen(),
            ),
          ).then((_) => _loadActivePrograms());
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark 
                ? AppTheme.primaryGreen.withOpacity(0.3) 
                : Colors.grey.withOpacity(0.2),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isGroup
                              ? const Color(0xFF6C63FF).withOpacity(isDark ? 0.18 : 0.1)
                              : const Color(0xFF2ECC71).withOpacity(isDark ? 0.18 : 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isGroup
                                ? const Color(0xFF6C63FF).withOpacity(0.3)
                                : const Color(0xFF2ECC71).withOpacity(0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          isGroup ? context.translate('home_type_group') : context.translate('home_type_mandiri'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isGroup ? const Color(0xFF6C63FF) : const Color(0xFF2ECC71),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isGroup ? item['title'] as String : context.translate('mandiri_title'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isGroup && item['code'] != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '#${item['code']}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress / 100,
                            minHeight: 6,
                            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isGroup ? const Color(0xFF6C63FF) : const Color(0xFF2ECC71),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        progressText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
