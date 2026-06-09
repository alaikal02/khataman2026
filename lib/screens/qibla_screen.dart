import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_qiblah/flutter_qiblah.dart';
import '../theme/app_theme.dart';
import '../services/prayer_time_service.dart';

class QiblaScreen extends StatefulWidget {
  const QiblaScreen({Key? key}) : super(key: key);

  @override
  State<QiblaScreen> createState() => _QiblaScreenState();
}

class _QiblaScreenState extends State<QiblaScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _hasSensor = false;
  String _locationName = 'Memuat lokasi...';
  double _distanceToKaaba = 0;

  // Kaaba coordinates
  static const double _kaabaLat = 21.4225;
  static const double _kaabaLng = 39.8262;

  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _checkSensorAndLocation();
  }

  Future<void> _checkSensorAndLocation() async {
    try {
      final deviceSupport = await FlutterQiblah.androidDeviceSensorSupport();
      bool hasSensor = deviceSupport ?? false;

      // Double-check: some Android devices have the sensor and stream works, but the native check returns false
      if (!hasSensor) {
        try {
          final completer = Completer<bool>();
          StreamSubscription? sub;
          sub = FlutterQiblah.qiblahStream.listen(
            (data) {
              if (!completer.isCompleted) {
                completer.complete(true);
              }
              sub?.cancel();
            },
            onError: (err) {
              if (!completer.isCompleted) {
                completer.complete(false);
              }
              sub?.cancel();
            },
            cancelOnError: true,
          );

          // Timeout after 800ms
          final success = await completer.future.timeout(
            const Duration(milliseconds: 800),
            onTimeout: () {
              sub?.cancel();
              return false;
            },
          );
          if (success) {
            hasSensor = true;
          }
        } catch (e) {
          debugPrint('Qibla stream fallback verification error: $e');
        }
      }

      // Load location name
      final savedCity = await PrayerTimeService.getSavedCity();
      final saved = await PrayerTimeService.getSavedLocation();
      String locName = savedCity ?? 'Lokasi Anda';

      double dist = 0;
      if (saved != null) {
        dist = _calculateDistance(saved['lat']!, saved['lng']!, _kaabaLat, _kaabaLng);
        if (savedCity == null) {
          locName = await PrayerTimeService.getLocationName(saved['lat']!, saved['lng']!);
        }
      }

      if (mounted) {
        setState(() {
          _hasSensor = hasSensor;
          _locationName = locName;
          _distanceToKaaba = dist;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Qibla sensor check error: $e');
      if (mounted) {
        setState(() {
          _hasSensor = false;
          _isLoading = false;
        });
      }
    }
  }

  /// Calculate distance between two coordinates in km (Haversine formula)
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth's radius in km
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * (math.pi / 180.0);

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryGreen),
                      )
                    : _hasSensor
                        ? _buildCompassView(context)
                        : _buildNoSensorFallback(context),
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
          const Expanded(
            child: Text(
              'Arah Kiblat',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ── COMPASS MODE (with sensor) ──────────────────────────

  Widget _buildCompassView(BuildContext context) {
    return StreamBuilder<QiblahDirection>(
      stream: FlutterQiblah.qiblahStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primaryGreen),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildNoSensorFallback(context);
        }

        final qiblah = snapshot.data!;
        final qiblaDirection = qiblah.qiblah;
        final northDirection = qiblah.direction;

        // Check if pointing towards Qibla (within ±5 degrees)
        final isPointingToQibla = qiblaDirection.abs() < 5;

        // Trigger haptic feedback when aligned
        if (isPointingToQibla) {
          HapticFeedback.lightImpact();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildLocationInfo(context),
              const SizedBox(height: 24),
              _buildCompassWidget(context, qiblaDirection, northDirection, isPointingToQibla),
              const SizedBox(height: 24),
              _buildDirectionInfo(context, qiblaDirection, isPointingToQibla),
              const SizedBox(height: 16),
              _buildCalibrationHint(context),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationInfo(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? AppTheme.primaryGreen.withOpacity(0.3)
              : AppTheme.primaryGreen.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(isDark ? 0.15 : 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.location_on_rounded,
                color: AppTheme.primaryGreen, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _locationName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (_distanceToKaaba > 0)
                  Text(
                    '${_distanceToKaaba.toStringAsFixed(0)} km ke Ka\'bah',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sensors_rounded, size: 14, color: AppTheme.primaryGreen),
                const SizedBox(width: 4),
                const Text(
                  'Kompas Aktif',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompassWidget(BuildContext context, double qiblaDirection,
      double northDirection, bool isAligned) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size.width * 0.7;

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        return Container(
          width: size + 40,
          height: size + 40,
          decoration: isAligned
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryGreen
                          .withOpacity(0.15 + _glowController.value * 0.2),
                      blurRadius: 30 + _glowController.value * 20,
                      spreadRadius: 5 + _glowController.value * 10,
                    ),
                  ],
                )
              : null,
          child: child,
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring
          Container(
            width: size + 20,
            height: size + 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isAligned
                    ? AppTheme.primaryGreen
                    : (isDark ? Colors.white24 : Colors.grey.shade300),
                width: 3,
              ),
            ),
          ),

          // Compass dial (rotates with north)
          AnimatedRotation(
            turns: -northDirection / 360,
            duration: const Duration(milliseconds: 300),
            child: SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _CompassDialPainter(
                  isDark: isDark,
                  isAligned: isAligned,
                ),
              ),
            ),
          ),

          // Qibla needle (rotates to qibla direction)
          AnimatedRotation(
            turns: -qiblaDirection / 360,
            duration: const Duration(milliseconds: 300),
            child: SizedBox(
              width: size * 0.85,
              height: size * 0.85,
              child: CustomPaint(
                painter: _QiblaNeedlePainter(isAligned: isAligned),
              ),
            ),
          ),

          // Center dot
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isAligned ? AppTheme.primaryGreen : Colors.grey,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (isAligned ? AppTheme.primaryGreen : Colors.grey)
                      .withOpacity(0.4),
                  blurRadius: 8,
                ),
              ],
            ),
          ),

          // Kaaba icon at the needle tip direction
          Positioned(
            top: 8,
            child: AnimatedRotation(
              turns: -qiblaDirection / 360,
              duration: const Duration(milliseconds: 300),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isAligned
                          ? AppTheme.primaryGreen
                          : (isDark ? Colors.white24 : Colors.grey.shade400),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '🕋',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionInfo(
      BuildContext context, double qiblaDirection, bool isAligned) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isAligned
            ? AppTheme.primaryGreen.withOpacity(isDark ? 0.15 : 0.08)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAligned
              ? AppTheme.primaryGreen.withOpacity(0.5)
              : (isDark
                  ? AppTheme.primaryGreen.withOpacity(0.3)
                  : AppTheme.primaryGreen.withOpacity(0.2)),
          width: isAligned ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            isAligned
                ? Icons.check_circle_rounded
                : Icons.explore_rounded,
            color: isAligned ? AppTheme.primaryGreen : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            isAligned
                ? 'Anda Menghadap Kiblat! ✅'
                : 'Putar perangkat Anda menuju Ka\'bah',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isAligned
                  ? AppTheme.primaryGreen
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${qiblaDirection.abs().toStringAsFixed(1)}° offset dari posisi Anda',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrationHint(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Tips: Gerakkan HP membentuk angka 8 untuk kalibrasi sensor kompas.',
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

  // ── FALLBACK MODE (no sensor) ───────────────────────────

  Widget _buildNoSensorFallback(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Warning banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(isDark ? 0.1 : 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.amber.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.sensors_off_rounded, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sensor Tidak Tersedia',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Perangkat Anda tidak memiliki sensor magnetometer. Menampilkan arah kiblat statis.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Static compass with qibla direction
          FutureBuilder<Map<String, double>?>(
            future: PrayerTimeService.getSavedLocation(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return Column(
                  children: [
                    const Icon(Icons.location_off_rounded,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'Lokasi tidak tersedia.\nBuka halaman Jadwal Shalat terlebih dahulu untuk mendeteksi lokasi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              }

              final lat = snapshot.data!['lat']!;
              final lng = snapshot.data!['lng']!;
              final bearing = _calculateBearing(lat, lng, _kaabaLat, _kaabaLng);

              return Column(
                children: [
                  // Static compass showing direction
                  SizedBox(
                    width: 250,
                    height: 250,
                    child: CustomPaint(
                      painter: _StaticQiblaPainter(
                        bearing: bearing,
                        isDark: isDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
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
                      children: [
                        const Text('🕋', style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 8),
                        Text(
                          'Arah Kiblat: ${bearing.toStringAsFixed(1)}° dari Utara',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Jarak ke Ka\'bah: ${_distanceToKaaba.toStringAsFixed(0)} km',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Dari: $_locationName',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Calculate bearing from point 1 to point 2 in degrees
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _toRad(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(_toRad(lat2));
    final x = math.cos(_toRad(lat1)) * math.sin(_toRad(lat2)) -
        math.sin(_toRad(lat1)) * math.cos(_toRad(lat2)) * math.cos(dLon);
    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360;
  }
}

// ── CUSTOM PAINTERS ──────────────────────────────────────

class _CompassDialPainter extends CustomPainter {
  final bool isDark;
  final bool isAligned;

  _CompassDialPainter({required this.isDark, required this.isAligned});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Draw tick marks
    final tickPaint = Paint()
      ..color = isDark ? Colors.white38 : Colors.grey.shade400
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final majorTickPaint = Paint()
      ..color = isDark ? Colors.white70 : Colors.grey.shade700
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 360; i += 5) {
      final angle = i * math.pi / 180;
      final isMajor = i % 30 == 0;
      final tickLength = isMajor ? 15.0 : 8.0;

      final outer = Offset(
        center.dx + radius * math.cos(angle - math.pi / 2),
        center.dy + radius * math.sin(angle - math.pi / 2),
      );
      final inner = Offset(
        center.dx + (radius - tickLength) * math.cos(angle - math.pi / 2),
        center.dy + (radius - tickLength) * math.sin(angle - math.pi / 2),
      );

      canvas.drawLine(inner, outer, isMajor ? majorTickPaint : tickPaint);
    }

    // Draw cardinal directions
    final directions = {'N': 0.0, 'E': 90.0, 'S': 180.0, 'W': 270.0};
    for (final entry in directions.entries) {
      final angle = entry.value * math.pi / 180 - math.pi / 2;
      final textRadius = radius - 28;
      final pos = Offset(
        center.dx + textRadius * math.cos(angle),
        center.dy + textRadius * math.sin(angle),
      );

      final isNorth = entry.key == 'N';
      final textPainter = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: TextStyle(
            fontSize: isNorth ? 18 : 14,
            fontWeight: FontWeight.bold,
            color: isNorth
                ? Colors.red
                : (isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QiblaNeedlePainter extends CustomPainter {
  final bool isAligned;

  _QiblaNeedlePainter({required this.isAligned});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final needleLength = size.height / 2 - 10;

    // Qibla direction needle (pointing up = towards qibla)
    final needlePaint = Paint()
      ..color = isAligned ? AppTheme.primaryGreen : const Color(0xFF6C63FF)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Draw needle line
    canvas.drawLine(
      center,
      Offset(center.dx, center.dy - needleLength),
      needlePaint,
    );

    // Draw arrowhead
    final arrowPaint = Paint()
      ..color = isAligned ? AppTheme.primaryGreen : const Color(0xFF6C63FF)
      ..style = PaintingStyle.fill;

    final arrowPath = Path()
      ..moveTo(center.dx, center.dy - needleLength - 8)
      ..lineTo(center.dx - 8, center.dy - needleLength + 8)
      ..lineTo(center.dx + 8, center.dy - needleLength + 8)
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StaticQiblaPainter extends CustomPainter {
  final double bearing;
  final bool isDark;

  _StaticQiblaPainter({required this.bearing, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Draw outer circle
    final circlePaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, circlePaint);

    // Draw tick marks
    final tickPaint = Paint()
      ..color = isDark ? Colors.white30 : Colors.grey.shade400
      ..strokeWidth = 1.5;

    for (int i = 0; i < 360; i += 15) {
      final angle = i * math.pi / 180 - math.pi / 2;
      final isMajor = i % 90 == 0;
      final tickLen = isMajor ? 12.0 : 6.0;

      final outer = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      final inner = Offset(
        center.dx + (radius - tickLen) * math.cos(angle),
        center.dy + (radius - tickLen) * math.sin(angle),
      );
      canvas.drawLine(inner, outer, tickPaint);
    }

    // Draw N label
    final nPainter = TextPainter(
      text: const TextSpan(
        text: 'N',
        style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    nPainter.layout();
    nPainter.paint(canvas, Offset(center.dx - nPainter.width / 2, 4));

    // Draw qibla direction line
    final qiblaAngle = bearing * math.pi / 180 - math.pi / 2;
    final qiblaPaint = Paint()
      ..color = AppTheme.primaryGreen
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final qiblaEnd = Offset(
      center.dx + (radius - 20) * math.cos(qiblaAngle),
      center.dy + (radius - 20) * math.sin(qiblaAngle),
    );
    canvas.drawLine(center, qiblaEnd, qiblaPaint);

    // Arrowhead
    final arrowPaint = Paint()
      ..color = AppTheme.primaryGreen
      ..style = PaintingStyle.fill;
    final arrowTip = Offset(
      center.dx + (radius - 8) * math.cos(qiblaAngle),
      center.dy + (radius - 8) * math.sin(qiblaAngle),
    );
    final arrowLeft = Offset(
      arrowTip.dx + 10 * math.cos(qiblaAngle + 2.6),
      arrowTip.dy + 10 * math.sin(qiblaAngle + 2.6),
    );
    final arrowRight = Offset(
      arrowTip.dx + 10 * math.cos(qiblaAngle - 2.6),
      arrowTip.dy + 10 * math.sin(qiblaAngle - 2.6),
    );
    final path = Path()
      ..moveTo(arrowTip.dx, arrowTip.dy)
      ..lineTo(arrowLeft.dx, arrowLeft.dy)
      ..lineTo(arrowRight.dx, arrowRight.dy)
      ..close();
    canvas.drawPath(path, arrowPaint);

    // Center dot
    canvas.drawCircle(center, 5, Paint()..color = AppTheme.primaryGreen);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
