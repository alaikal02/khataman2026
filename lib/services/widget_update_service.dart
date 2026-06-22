import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quran/quran.dart' as quran;
import 'prayer_time_service.dart';
import '../utils/localization.dart';

class WidgetUpdateService {
  /// Update Khataman Widget by fetching active programs from the database
  static Future<void> updateKhatamanWidget() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        await HomeWidget.saveWidgetData<int>('khataman_count', 0);
        await HomeWidget.updateWidget(
          name: 'KhatamanWidgetProvider',
          androidName: 'KhatamanWidgetProvider',
        );
        return;
      }

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
              'progress': progressPercent,
              'updated_at': latestUpdated,
            });
          }
        }
      } catch (e) {
        debugPrint('Widget: Error fetching mandiri: $e');
      }

      // 2. Fetch Active Group slots
      try {
        final slotsRes = await Supabase.instance.client
            .from('slot_khataman')
            .select('*, putaran_siklus!inner(*)')
            .eq('user_id', userId)
            .eq('putaran_siklus.status_aktif_selesai', 'AKTIF');

        final slotsList = slotsRes as List;
        if (slotsList.isNotEmpty) {
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
                'progress': progressPercent,
                'updated_at': latestUpdated,
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Widget: Error fetching group slots: $e');
      }

      // Sort by updated_at desc
      programs.sort((a, b) => (b['updated_at'] as DateTime).compareTo(a['updated_at'] as DateTime));

      await updateKhatamanWidgetWithData(programs);
    } catch (e) {
      debugPrint('Error updating khataman widget: $e');
    }
  }

  /// Update Khataman Widget by passing pre-fetched data directly
  static Future<void> updateKhatamanWidgetWithData(List<Map<String, dynamic>> programs) async {
    try {
      final count = programs.length > 2 ? 2 : programs.length;
      await HomeWidget.saveWidgetData<int>('khataman_count', count);

      // Save app language
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('app_language') ?? 'id';
      await HomeWidget.saveWidgetData<String>('app_language', lang);

      for (int i = 0; i < count; i++) {
        final prog = programs[i];
        await HomeWidget.saveWidgetData<String>('khataman_title_$i', prog['title'] as String);
        await HomeWidget.saveWidgetData<double>('khataman_progress_$i', (prog['progress'] as num).toDouble());
        await HomeWidget.saveWidgetData<String>('khataman_type_$i', prog['type'] as String);
      }

      await HomeWidget.updateWidget(
        name: 'KhatamanWidgetProvider',
        androidName: 'KhatamanWidgetProvider',
      );
    } catch (e) {
      debugPrint('Error updating khataman widget with data: $e');
    }
  }

  /// Calculate and update Prayer times on the Home Screen Widget
  static Future<void> updatePrayerWidget() async {
    try {
      double? lat;
      double? lng;
      String city = 'Jakarta, Indonesia (Default)';
      String calcMethod = 'singapore';
      String madhab = 'syafii';

      final savedLoc = await PrayerTimeService.getSavedLocation();
      if (savedLoc != null && savedLoc['lat'] != null && savedLoc['lng'] != null) {
        lat = savedLoc['lat'];
        lng = savedLoc['lng'];
        city = await PrayerTimeService.getSavedCity() ?? 'Lokasi';
        calcMethod = await PrayerTimeService.getCalcMethod();
        madhab = await PrayerTimeService.getMadhab();
      } else {
        // Fallback default
        lat = -6.2088;
        lng = 106.8456;
        city = 'Jakarta, Indonesia (Default)';
        calcMethod = 'singapore';
        madhab = 'syafii';
      }

      final prayerTimes = PrayerTimeService.calculatePrayerTimes(
        lat: lat!,
        lng: lng!,
        date: DateTime.now(),
        locationName: city,
        calcMethod: calcMethod,
        madhab: madhab,
      );

      final nextPrayer = prayerTimes.getNextPrayer() ?? prayerTimes.entries.firstWhere((e) => e.name == 'Subuh');

      String formatTime(DateTime dt) {
        return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      }

      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('app_language') ?? 'id';
      await HomeWidget.saveWidgetData<String>('app_language', lang);

      // Translate location if it is the default Jakarta
      String displayCity = city;
      if (city == 'Jakarta, Indonesia (Default)') {
        displayCity = localizedStrings[lang]?['prayer_default_location'] ?? city;
      }

      // Save location and date
      await HomeWidget.saveWidgetData<String>('prayer_location', displayCity);

      final isEn = lang == 'en';
      final days = isEn 
          ? ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
          : ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
      final months = isEn
          ? ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
          : ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
      
      final now = DateTime.now();
      final dateStr = "${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}";
      
      await HomeWidget.saveWidgetData<String>('prayer_date', dateStr);

      // Save translated next prayer name and key
      final prayerKey = 'prayer_${nextPrayer.name.toLowerCase()}';
      final nextPrayerDisplayName = localizedStrings[lang]?[prayerKey] ?? nextPrayer.name;
      
      await HomeWidget.saveWidgetData<String>('prayer_next_name', nextPrayerDisplayName);
      await HomeWidget.saveWidgetData<String>('prayer_next_key', nextPrayer.name.toLowerCase());
      await HomeWidget.saveWidgetData<String>('prayer_next_time', formatTime(nextPrayer.time));

      // Save fard and extra prayer times
      for (final entry in prayerTimes.entries) {
        await HomeWidget.saveWidgetData<String>('prayer_time_${entry.name.toLowerCase()}', formatTime(entry.time));
      }

      await HomeWidget.updateWidget(
        name: 'PrayerWidgetProvider',
        androidName: 'PrayerWidgetProvider',
      );
    } catch (e) {
      debugPrint('Error updating prayer widget: $e');
    }
  }
}
