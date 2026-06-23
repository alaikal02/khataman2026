import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../utils/localization.dart';
import '../theme/app_theme.dart';
import '../services/prayer_time_service.dart';
import '../services/azan_notification_service.dart';
import '../services/widget_update_service.dart';
import 'package:geocoding/geocoding.dart';

class PrayerTimeScreen extends StatefulWidget {
  const PrayerTimeScreen({Key? key}) : super(key: key);

  @override
  State<PrayerTimeScreen> createState() => _PrayerTimeScreenState();
}

class _PrayerTimeScreenState extends State<PrayerTimeScreen>
    with SingleTickerProviderStateMixin {
  static Map<String, DateTime>? _cachedPrayerTimes;
  static double? _cachedLatitude;
  static double? _cachedLongitude;
  static String? _cachedCityName;

  static DailyPrayerTimes? _reconstructFromCache() {
    if (_cachedPrayerTimes == null ||
        _cachedLatitude == null ||
        _cachedLongitude == null ||
        _cachedCityName == null) {
      return null;
    }

    final staticMetadata = {
      'Imsak': {'arabic': 'إمساك', 'fard': false},
      'Subuh': {'arabic': 'الفجر', 'fard': true},
      'Syuruk': {'arabic': 'الشروق', 'fard': false},
      'Dhuha': {'arabic': 'الضحى', 'fard': false},
      'Dzuhur': {'arabic': 'الظهر', 'fard': true},
      'Ashar': {'arabic': 'العصر', 'fard': true},
      'Maghrib': {'arabic': 'المغرب', 'fard': true},
      'Isya': {'arabic': 'العشاء', 'fard': true},
    };

    final entries = <PrayerTimeEntry>[];
    staticMetadata.forEach((name, meta) {
      final time = _cachedPrayerTimes![name];
      if (time != null) {
        entries.add(PrayerTimeEntry(
          name: name,
          arabicName: meta['arabic'] as String,
          time: time,
          isFard: meta['fard'] as bool,
        ));
      }
    });

    return DailyPrayerTimes(
      entries: entries,
      locationName: _cachedCityName!,
      latitude: _cachedLatitude!,
      longitude: _cachedLongitude!,
      date: _cachedPrayerTimes!.values.first,
    );
  }

  DailyPrayerTimes? _prayerTimes;
  bool _isLoading = true;
  bool _isBackgroundRefreshing = false;
  bool _isOffline = false;
  Timer? _offlineRetryTimer;
  String? _errorMessage;
  Timer? _countdownTimer;
  Duration _timeUntilNext = Duration.zero;
  String _nextPrayerName = '';

  // Settings
  String _calcMethod = 'muslim_world_league';
  String _madhab = 'syafii';
  bool _useGps = true;
  bool _azanEnabled = false;
  Map<String, bool> _azanToggles = {
    'Subuh': true, 'Dzuhur': true, 'Ashar': true, 'Maghrib': true, 'Isya': true,
  };
  String _azanSound = 'default';

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingPreview = false;
  final TextEditingController _citySearchController = TextEditingController();

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    final today = DateTime.now();
    if (_cachedPrayerTimes != null) {
      final cachedDate = _cachedPrayerTimes!.values.first;
      if (cachedDate.year != today.year ||
          cachedDate.month != today.month ||
          cachedDate.day != today.day) {
        _cachedPrayerTimes = null;
        _cachedLatitude = null;
        _cachedLongitude = null;
        _cachedCityName = null;
      }
    }

    _prayerTimes = _reconstructFromCache();
    _isLoading = _prayerTimes == null;

    if (_prayerTimes != null) {
      _startCountdown();
    }

    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _calcMethod = await PrayerTimeService.getCalcMethod();
    _madhab = await PrayerTimeService.getMadhab();
    _useGps = await PrayerTimeService.getUseGps();
    _azanEnabled = await AzanNotificationService.isAzanEnabled();
    _azanToggles = await AzanNotificationService.getAzanToggles();
    _azanSound = await AzanNotificationService.getAzanSound();
    await _loadPrayerTimes();
  }

  Future<void> _playAzanPreview(String soundKey, StateSetter setStateSheet) async {
    try {
      await _audioPlayer.stop();
      if (soundKey == 'silent' || soundKey == 'default') {
        setStateSheet(() {
          _isPlayingPreview = false;
        });
        return;
      }

      setStateSheet(() {
        _isPlayingPreview = true;
      });

      await _audioPlayer.play(AssetSource('audio/azan_$soundKey.mp3'));

      _audioPlayer.onPlayerComplete.listen((event) {
        if (mounted) {
          setStateSheet(() {
            _isPlayingPreview = false;
          });
        }
      });
    } catch (e) {
      debugPrint('Error playing preview: $e');
      if (mounted) {
        setStateSheet(() {
          _isPlayingPreview = false;
        });
      }
    }
  }

  Future<void> _stopAzanPreview(StateSetter setStateSheet) async {
    await _audioPlayer.stop();
    setStateSheet(() {
      _isPlayingPreview = false;
    });
  }

  Future<void> _loadPrayerTimes({bool isManual = false}) async {
    if (!mounted) return;

    if (isManual) {
      _cachedPrayerTimes = null;
      _cachedLatitude = null;
      _cachedLongitude = null;
      _cachedCityName = null;
    }

    try {
      final isOnline = await _checkInternet();
      if (!isOnline) {
        if (mounted) {
          setState(() {
            _isOffline = true;
            _isLoading = false;
            _isBackgroundRefreshing = false;
          });
          _startOfflineRetryTimer();
        }
        return;
      }

      if (_cachedPrayerTimes == null) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      } else if (!isManual) {
        setState(() {
          _isBackgroundRefreshing = true;
        });
      }

      double? lat, lng;
      String locationName = 'Lokasi Tidak Diketahui';

      if (_useGps) {
        final position = await PrayerTimeService.getCurrentLocation();
        if (position != null) {
          lat = position.latitude;
          lng = position.longitude;
          locationName = await PrayerTimeService.getLocationName(lat, lng);

          // Auto-detect method & madhab on first GPS fetch
          final savedCity = await PrayerTimeService.getSavedCity();
          if (savedCity == null || savedCity.isEmpty) {
            _calcMethod = await PrayerTimeService.autoDetectCalcMethod(lat, lng);
            _madhab = await PrayerTimeService.autoDetectMadhab(lat, lng);
            await PrayerTimeService.setCalcMethod(_calcMethod);
            await PrayerTimeService.setMadhab(_madhab);
          }

          // Save location
          await PrayerTimeService.saveLocation(lat, lng, locationName);
        }
      }

      // Fallback to saved location
      if (lat == null || lng == null) {
        final saved = await PrayerTimeService.getSavedLocation();
        if (saved != null) {
          lat = saved['lat']!;
          lng = saved['lng']!;
          locationName = await PrayerTimeService.getSavedCity() ?? 'Lokasi Tersimpan';
        }
      }

      if (lat == null || lng == null) {
        // Default: Jakarta
        lat = -6.2088;
        lng = 106.8456;
        locationName = 'Jakarta, Indonesia (Default)';
        _calcMethod = 'singapore';
        _madhab = 'syafii';
      }

      final prayerTimes = PrayerTimeService.calculatePrayerTimes(
        lat: lat,
        lng: lng,
        date: DateTime.now(),
        locationName: locationName,
        calcMethod: _calcMethod,
        madhab: _madhab,
      );

      _cachedPrayerTimes = {
        for (final entry in prayerTimes.entries) entry.name: entry.time
      };
      _cachedLatitude = lat;
      _cachedLongitude = lng;
      _cachedCityName = locationName;

      if (mounted) {
        setState(() {
          _prayerTimes = prayerTimes;
          _isLoading = false;
          _isBackgroundRefreshing = false;
          _isOffline = false;
        });
        _startCountdown();

        // Schedule azan notifications
        await AzanNotificationService.scheduleAzanNotifications(prayerTimes);
        WidgetUpdateService.updatePrayerWidget();
      }
      _offlineRetryTimer?.cancel();
      _offlineRetryTimer = null;
    } catch (e) {
      final isOnline = await _checkInternet();
      if (!isOnline) {
        if (mounted) {
          setState(() {
            _isOffline = true;
            _isLoading = false;
            _isBackgroundRefreshing = false;
          });
          _startOfflineRetryTimer();
        }
      } else {
        debugPrint('Error loading prayer times: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isBackgroundRefreshing = false;
            _isOffline = false;
            _errorMessage = 'Gagal memuat jadwal shalat: $e';
          });
        }
        _offlineRetryTimer?.cancel();
        _offlineRetryTimer = null;
      }
    }
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('dns.google').timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _startOfflineRetryTimer() {
    _offlineRetryTimer?.cancel();
    _offlineRetryTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final isOnline = await _checkInternet();
      if (isOnline) {
        timer.cancel();
        _offlineRetryTimer = null;
        _loadPrayerTimes();
      }
    });
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    if (_prayerTimes == null || !mounted) return;
    final next = _prayerTimes!.getNextPrayer();
    if (next != null) {
      final diff = next.time.difference(DateTime.now());
      if (diff.isNegative) {
        // Prayer time has passed, reload
        _loadPrayerTimes();
        return;
      }
      setState(() {
        _timeUntilNext = diff;
        _nextPrayerName = next.name;
      });
    } else {
      setState(() {
        _timeUntilNext = Duration.zero;
        _nextPrayerName = '';
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    _audioPlayer.dispose();
    _citySearchController.dispose();
    _offlineRetryTimer?.cancel();
    super.dispose();
  }

  String _formatCountdown(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Provider.of<SettingsProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF161B22) : const Color(0xFFEEEEEE),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBgGradient : AppTheme.lightBgGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(context),
              _buildOfflineBanner(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                      )
                    : _errorMessage != null
                        ? _buildErrorWidget()
                        : RefreshIndicator(
                            color: AppTheme.primaryGreen,
                            onRefresh: () => _loadPrayerTimes(isManual: true),
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                children: [
                                  const SizedBox(height: 8),
                                  _buildLocationHeader(context),
                                  const SizedBox(height: 16),
                                  _buildCountdownCard(context),
                                  const SizedBox(height: 20),
                                  _buildPrayerTimesList(context),
                                  const SizedBox(height: 16),
                                  _buildMethodInfo(context),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios_rounded,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          Expanded(
            child: Text(
              context.translate('prayer_title'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            onPressed: _showSettingsSheet,
            icon: Icon(Icons.tune_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            tooltip: context.translate('prayer_tooltip_settings'),
          ),
        ],
      ),
    );
  }

  String _resolveLocationName(String? name) {
    if (name == null || name == 'Memuat lokasi...') {
      return context.translate('qibla_loading_location');
    }
    if (name == 'Lokasi Tidak Diketahui') {
      return context.translate('prayer_unknown_location');
    }
    if (name == 'Lokasi Tersimpan') {
      return context.translate('prayer_saved_location');
    }
    if (name == 'Jakarta, Indonesia (Default)') {
      return context.translate('prayer_default_location');
    }
    return name;
  }

  Widget _buildLocationHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primaryGreen.withOpacity(isDark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _useGps ? Icons.gps_fixed_rounded : Icons.location_on_rounded,
            color: AppTheme.primaryGreen,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _resolveLocationName(_prayerTimes?.locationName),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _getHijriDateLabel(),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => _loadPrayerTimes(isManual: true),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: Text(context.translate('prayer_btn_refresh')),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primaryGreen),
        ),
      ],
    );
  }

  String _getHijriDateLabel() {
    final now = DateTime.now();
    final dayNames = [
      'day_monday',
      'day_tuesday',
      'day_wednesday',
      'day_thursday',
      'day_friday',
      'day_saturday',
      'day_sunday'
    ];
    final monthNames = [
      'month_january',
      'month_february',
      'month_march',
      'month_april',
      'month_may',
      'month_june',
      'month_july',
      'month_august',
      'month_september',
      'month_october',
      'month_november',
      'month_december'
    ];
    final dayName = context.translate(dayNames[now.weekday - 1]);
    final monthName = context.translate(monthNames[now.month - 1]);
    return '$dayName, ${now.day} $monthName ${now.year}';
  }

  Widget _buildCountdownCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasNext = _nextPrayerName.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF1A4D3E), Color(0xFF0D2B20)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFF2ECC71), Color(0xFF1A8A4A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryGreen.withOpacity(isDark ? 0.25 : 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                hasNext ? context.translate('prayer_next_prayer') : context.translate('prayer_all_done'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.85),
                  letterSpacing: 0.5,
                ),
              ),
              if (_isBackgroundRefreshing) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white70,
                  ),
                ),
              ],
            ],
          ),
          if (hasNext) ...[
            const SizedBox(height: 6),
            Text(
              context.translate('prayer_${_nextPrayerName.toLowerCase()}'),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.7 + (_pulseController.value * 0.3),
                  child: child,
                );
              },
              child: Text(
                _formatCountdown(_timeUntilNext),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: 4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _prayerTimes?.getNextPrayer() != null
                  ? context.translate('prayer_at_time').replaceAll('{time}', _formatTime(_prayerTimes!.getNextPrayer()!.time))
                  : '',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.75),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Icon(Icons.check_circle_outline_rounded,
                color: Colors.white.withOpacity(0.8), size: 48),
            const SizedBox(height: 8),
            Text(
              context.translate('prayer_alhamdulillah'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrayerTimesList(BuildContext context) {
    if (_prayerTimes == null) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppTheme.primaryGreen.withOpacity(0.3)
              : AppTheme.primaryGreen.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: _prayerTimes!.entries.asMap().entries.map((mapEntry) {
          final idx = mapEntry.key;
          final entry = mapEntry.value;
          final isNext = _nextPrayerName == entry.name;
          final isPast = entry.time.isBefore(now);
          final isLast = idx == _prayerTimes!.entries.length - 1;

          return Column(
            children: [
              _buildPrayerRow(context, entry, isNext: isNext, isPast: isPast),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 56,
                  color: isDark
                      ? AppTheme.primaryGreen.withOpacity(0.12)
                      : AppTheme.primaryGreen.withOpacity(0.08),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPrayerRow(BuildContext context, PrayerTimeEntry entry,
      {required bool isNext, required bool isPast}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color iconColor;
    Color bgColor;
    if (isNext) {
      iconColor = AppTheme.primaryGreen;
      bgColor = AppTheme.primaryGreen.withOpacity(isDark ? 0.15 : 0.08);
    } else {
      iconColor = Theme.of(context).colorScheme.onSurfaceVariant;
      bgColor = Colors.transparent;
    }

    final IconData prayerIcon;
    switch (entry.name) {
      case 'Imsak':
        prayerIcon = Icons.dark_mode_rounded;
        break;
      case 'Subuh':
        prayerIcon = Icons.wb_twilight_rounded;
        break;
      case 'Syuruk':
        prayerIcon = Icons.wb_sunny_rounded;
        break;
      case 'Dhuha':
        prayerIcon = Icons.light_mode_rounded;
        break;
      case 'Dzuhur':
        prayerIcon = Icons.wb_sunny_rounded;
        break;
      case 'Ashar':
        prayerIcon = Icons.sunny_snowing;
        break;
      case 'Maghrib':
        prayerIcon = Icons.wb_twilight_rounded;
        break;
      case 'Isya':
        prayerIcon = Icons.nightlight_round;
        break;
      default:
        prayerIcon = Icons.access_time_rounded;
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isNext
                  ? AppTheme.primaryGreen.withOpacity(isDark ? 0.2 : 0.12)
                  : iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(prayerIcon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.translate('prayer_${entry.name.toLowerCase()}'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isNext ? FontWeight.bold : FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  entry.arabicName,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                    fontFamily: 'LPMQ-IsepMisbah',
                  ),
                ),
              ],
            ),
          ),
          if (entry.isFard)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                context.translate('prayer_fard_badge'),
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          Text(
            _formatTime(entry.time),
            style: TextStyle(
              fontSize: 16,
              fontWeight: isNext ? FontWeight.bold : FontWeight.w600,
              fontFamily: 'monospace',
              color: isNext
                  ? AppTheme.primaryGreen
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _getLocalizedMethodName(String method) {
    if (method == 'singapore') return context.translate('method_singapore');
    if (method == 'muslim_world_league') return context.translate('method_muslim_world_league');
    if (method == 'egyptian') return context.translate('method_egyptian');
    if (method == 'karachi') return context.translate('method_karachi');
    if (method == 'umm_al_qura') return context.translate('method_umm_al_qura');
    if (method == 'dubai') return context.translate('method_dubai');
    if (method == 'kuwait') return context.translate('method_kuwait');
    if (method == 'turkey') return context.translate('method_turkey');
    if (method == 'tehran') return context.translate('method_tehran');
    return PrayerTimeService.calcMethodOptions[method] ?? method;
  }

  String _getLocalizedMadhabName(String madhab) {
    if (madhab == 'syafii') return context.translate('madhab_syafii');
    if (madhab == 'hanafi') return context.translate('madhab_hanafi');
    return PrayerTimeService.madhabOptions[madhab] ?? madhab;
  }

  String _getLocalizedSoundName(String soundKey) {
    if (soundKey == 'default') return context.translate('sound_default');
    if (soundKey == 'silent') return context.translate('sound_silent');
    if (soundKey == 'makkah') return context.translate('sound_makkah');
    if (soundKey == 'madinah') return context.translate('sound_madinah');
    return AzanNotificationService.azanSoundOptions[soundKey] ?? soundKey;
  }

  Widget _buildMethodInfo(BuildContext context) {
    final methodName = _getLocalizedMethodName(_calcMethod);
    final madhabName = _getLocalizedMadhabName(_madhab);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              context.translate('prayer_method_madhab_info')
                  .replaceAll('{method}', methodName)
                  .replaceAll('{madhab}', madhabName),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_rounded, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              context.translate('prayer_err_general') + (_errorMessage != null ? ': $_errorMessage' : ''),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadPrayerTimes(isManual: true),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.translate('prayer_btn_retry')),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsSheet() {
    _citySearchController.clear();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String selectedMethod = _calcMethod;
    String selectedMadhab = _madhab;
    bool localAzanEnabled = _azanEnabled;
    Map<String, bool> localAzanToggles = Map.from(_azanToggles);
    String localAzanSound = _azanSound;

    bool localUseGps = _useGps;
    String localCityName = _prayerTimes?.locationName ?? 'Jakarta, Indonesia (Default)';
    double localLatitude = _cachedLatitude ?? -6.2088;
    double localLongitude = _cachedLongitude ?? 106.8456;

    bool isSearchingLocation = false;
    String? locationSearchError;
    String? locationSearchSuccess;

    Future<void> performCitySearch(StateSetter setStateSheet) async {
      final query = _citySearchController.text.trim();
      if (query.isEmpty) {
        setStateSheet(() {
          locationSearchError = context.translate('prayer_err_enter_city');
          locationSearchSuccess = null;
        });
        return;
      }

      setStateSheet(() {
        isSearchingLocation = true;
        locationSearchError = null;
        locationSearchSuccess = null;
      });

      try {
        final isOnline = await _checkInternet();
        if (!isOnline) {
          setStateSheet(() {
            isSearchingLocation = false;
            locationSearchError = context.translate('prayer_err_no_internet');
          });
          return;
        }

        final locations = await locationFromAddress(query);
        if (locations.isEmpty) {
          setStateSheet(() {
            isSearchingLocation = false;
            locationSearchError = context.translate('prayer_err_city_not_found').replaceAll('{query}', query);
          });
          return;
        }

        final loc = locations.first;
        final resolvedName = await PrayerTimeService.getLocationName(loc.latitude, loc.longitude);

        setStateSheet(() {
          localLatitude = loc.latitude;
          localLongitude = loc.longitude;
          localCityName = resolvedName;
          isSearchingLocation = false;
          locationSearchSuccess = context.translate('prayer_success_city_changed').replaceAll('{resolvedName}', resolvedName);
          locationSearchError = null;
        });
      } catch (e) {
        debugPrint('Error searching location: $e');
        setStateSheet(() {
          isSearchingLocation = false;
          locationSearchError = context.translate('prayer_err_failed_search');
        });
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).padding.bottom +
                    24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.translate('prayer_settings_title'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Section Lokasi
                    Text(
                      context.translate('prayer_settings_loc_section'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        context.translate('prayer_settings_use_gps'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      subtitle: Text(
                        context.translate('prayer_settings_use_gps_sub'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: localUseGps,
                      activeColor: AppTheme.primaryGreen,
                      onChanged: (val) {
                        setStateSheet(() {
                          localUseGps = val;
                          locationSearchError = null;
                          locationSearchSuccess = null;
                        });
                      },
                    ),
                    if (!localUseGps) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _citySearchController,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: context.translate('prayer_settings_city_hint'),
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? AppTheme.primaryGreen.withOpacity(0.3)
                                        : AppTheme.primaryGreen.withOpacity(0.2),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? AppTheme.primaryGreen.withOpacity(0.2)
                                        : AppTheme.primaryGreen.withOpacity(0.15),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 1.5),
                                ),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                              ),
                              onSubmitted: (_) => performCitySearch(setStateSheet),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 40,
                            child: ElevatedButton(
                              onPressed: isSearchingLocation ? null : () => performCitySearch(setStateSheet),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryGreen.withOpacity(0.15),
                                foregroundColor: AppTheme.primaryGreen,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: isSearchingLocation
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppTheme.primaryGreen,
                                      ),
                                    )
                                  : const Icon(Icons.search_rounded, size: 18),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (locationSearchError != null)
                        Text(
                          locationSearchError!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                        ),
                      if (locationSearchSuccess != null)
                        Text(
                          locationSearchSuccess!,
                          style: const TextStyle(color: AppTheme.primaryGreen, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      if (locationSearchError == null && locationSearchSuccess == null)
                        Text(
                          context.translate('prayer_settings_active_loc').replaceAll('{city}', _resolveLocationName(localCityName)),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                    ],
                    const Divider(height: 32),

                    // Method dropdown
                    Text(
                      context.translate('prayer_settings_calc_title'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? AppTheme.primaryGreen.withOpacity(0.3)
                              : AppTheme.primaryGreen.withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedMethod,
                          isExpanded: true,
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: AppTheme.primaryGreen),
                          items: PrayerTimeService.calcMethodOptions.entries.map((e) {
                            return DropdownMenuItem(
                              value: e.key,
                              child: Text(_getLocalizedMethodName(e.key), style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setStateSheet(() => selectedMethod = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Madhab dropdown
                    Text(
                      context.translate('prayer_settings_madhab_title'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark
                              ? AppTheme.primaryGreen.withOpacity(0.3)
                              : AppTheme.primaryGreen.withOpacity(0.2),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedMadhab,
                          isExpanded: true,
                          dropdownColor: Theme.of(context).colorScheme.surface,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: AppTheme.primaryGreen),
                          items: PrayerTimeService.madhabOptions.entries.map((e) {
                            return DropdownMenuItem(
                              value: e.key,
                              child: Text(_getLocalizedMadhabName(e.key), style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setStateSheet(() => selectedMadhab = val);
                            }
                          },
                        ),
                      ),
                    ),
                    
                    const Divider(height: 32),
                    
                    // Notifikasi Azan Toggle
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.translate('prayer_settings_azan_alarm'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              localAzanEnabled ? context.translate('status_active') : context.translate('status_inactive'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Switch(
                          value: localAzanEnabled,
                          activeColor: AppTheme.primaryGreen,
                          onChanged: (val) {
                            setStateSheet(() {
                              localAzanEnabled = val;
                              if (!val) {
                                _stopAzanPreview(setStateSheet);
                              }
                            });
                          },
                        ),
                      ],
                    ),

                    if (localAzanEnabled) ...[
                      const SizedBox(height: 16),
                      Text(
                        context.translate('prayer_settings_azan_reminder_time'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: localAzanToggles.entries.map((entry) {
                          final prayer = entry.key;
                          final isToggled = entry.value;
                          return ChoiceChip(
                            label: Text(context.translate('prayer_${prayer.toLowerCase()}'), style: const TextStyle(fontSize: 12)),
                            selected: isToggled,
                            selectedColor: AppTheme.primaryGreen.withOpacity(0.2),
                            checkmarkColor: AppTheme.primaryGreen,
                            labelStyle: TextStyle(
                              color: isToggled
                                  ? AppTheme.primaryGreen
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: isToggled ? FontWeight.bold : FontWeight.normal,
                            ),
                            onSelected: (selected) {
                              setStateSheet(() {
                                localAzanToggles[prayer] = selected;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.translate('prayer_settings_azan_sound_selection'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isDark
                                      ? AppTheme.primaryGreen.withOpacity(0.3)
                                      : AppTheme.primaryGreen.withOpacity(0.2),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: localAzanSound,
                                  isExpanded: true,
                                  dropdownColor: Theme.of(context).colorScheme.surface,
                                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                                      color: AppTheme.primaryGreen),
                                  items: AzanNotificationService.azanSoundOptions.entries.map((e) {
                                    return DropdownMenuItem(
                                      value: e.key,
                                      child: Text(_getLocalizedSoundName(e.key), style: const TextStyle(fontSize: 13)),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setStateSheet(() {
                                        localAzanSound = val;
                                        _stopAzanPreview(setStateSheet);
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (localAzanSound != 'silent' && localAzanSound != 'default') ...[
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              onPressed: () {
                                if (_isPlayingPreview) {
                                    _stopAzanPreview(setStateSheet);
                                } else {
                                  _playAzanPreview(localAzanSound, setStateSheet);
                                }
                              },
                              icon: Icon(
                                _isPlayingPreview ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                color: AppTheme.primaryGreen,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.primaryGreen.withOpacity(0.15),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          // Stop preview if playing
                          await _audioPlayer.stop();
                          _isPlayingPreview = false;

                          await PrayerTimeService.setUseGps(localUseGps);
                          if (!localUseGps) {
                            await PrayerTimeService.saveLocation(
                              localLatitude,
                              localLongitude,
                              localCityName,
                            );
                          }

                          await PrayerTimeService.setCalcMethod(selectedMethod);
                          await PrayerTimeService.setMadhab(selectedMadhab);
                          
                          await AzanNotificationService.setAzanEnabled(localAzanEnabled);
                          for (final entry in localAzanToggles.entries) {
                            await AzanNotificationService.setAzanToggle(entry.key, entry.value);
                          }
                          await AzanNotificationService.setAzanSound(localAzanSound);

                          if (mounted) {
                            Navigator.pop(ctx);
                            setState(() {
                              _useGps = localUseGps;
                              _calcMethod = selectedMethod;
                              _madhab = selectedMadhab;
                              _azanEnabled = localAzanEnabled;
                              _azanToggles = Map.from(localAzanToggles);
                              _azanSound = localAzanSound;

                              if (!localUseGps) {
                                _cachedLatitude = localLatitude;
                                _cachedLongitude = localLongitude;
                                _cachedCityName = localCityName;
                              }
                            });
                            _loadPrayerTimes(isManual: true);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(context.translate('prayer_settings_btn_save'),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // Stop preview when bottom sheet is dismissed
      _audioPlayer.stop();
      _isPlayingPreview = false;
    });
  }

  Widget _buildOfflineBanner() {
    if (!_isOffline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.redAccent.withOpacity(0.9),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            context.translate('prayer_offline_banner'),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
