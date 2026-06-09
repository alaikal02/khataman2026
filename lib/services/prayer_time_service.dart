import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:adhan_dart/adhan_dart.dart';

/// Data class for a single prayer time entry
class PrayerTimeEntry {
  final String name;
  final String arabicName;
  final DateTime time;
  final bool isFard; // true = wajib (5 shalat fardhu)

  PrayerTimeEntry({
    required this.name,
    required this.arabicName,
    required this.time,
    required this.isFard,
  });
}

/// Holds all prayer times for a given day
class DailyPrayerTimes {
  final List<PrayerTimeEntry> entries;
  final String locationName;
  final double latitude;
  final double longitude;
  final DateTime date;

  DailyPrayerTimes({
    required this.entries,
    required this.locationName,
    required this.latitude,
    required this.longitude,
    required this.date,
  });

  /// Get the next upcoming prayer from now
  PrayerTimeEntry? getNextPrayer() {
    final now = DateTime.now();
    for (final entry in entries) {
      if (entry.time.isAfter(now)) {
        return entry;
      }
    }
    return null; // all prayers for today have passed
  }

  /// Get the current active prayer (the one we're in the window of)
  PrayerTimeEntry? getCurrentPrayer() {
    final now = DateTime.now();
    PrayerTimeEntry? current;
    for (final entry in entries) {
      if (entry.time.isBefore(now) || entry.time.isAtSameMomentAs(now)) {
        current = entry;
      } else {
        break;
      }
    }
    return current;
  }

  /// Get duration until next prayer
  Duration? getTimeUntilNextPrayer() {
    final next = getNextPrayer();
    if (next == null) return null;
    return next.time.difference(DateTime.now());
  }
}

class PrayerTimeService {
  // SharedPreferences keys
  static const _keyUseGps = 'prayer_use_gps';
  static const _keySavedLat = 'prayer_saved_lat';
  static const _keySavedLng = 'prayer_saved_lng';
  static const _keySavedCity = 'prayer_saved_city';
  static const _keyCalcMethod = 'prayer_calc_method';
  static const _keyMadhab = 'prayer_madhab';

  // Country codes where Syafi'i madhab is majority
  static const _syafiiCountries = {
    'ID', // Indonesia
    'MY', // Malaysia
    'BN', // Brunei
    'SG', // Singapore
    'PH', // Philippines
    'TH', // Thailand
    'SO', // Somalia
    'DJ', // Djibouti
    'ER', // Eritrea
    'KE', // Kenya
    'TZ', // Tanzania
    'KM', // Comoros
    'YE', // Yemen
    'MV', // Maldives
    'LK', // Sri Lanka
    'OM', // Oman
  };

  // ASEAN country codes (use Kemenag RI / Singapore method)
  static const _aseanCountries = {
    'ID', 'MY', 'BN', 'SG', 'PH', 'TH', 'VN', 'LA', 'KH', 'MM', 'TL',
  };

  /// Request location permission and get current GPS position
  static Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('📍 Location services are disabled.');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('📍 Location permission denied.');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('📍 Location permission permanently denied.');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // Lazy fetch — hemat baterai
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      debugPrint('📍 Error getting location: $e');
      return null;
    }
  }

  /// Reverse geocode coordinates to a city/locality name
  static Future<String> getLocationName(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final pm = placemarks.first;
        final city = pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea ?? '';
        final country = pm.country ?? '';
        if (city.isNotEmpty && country.isNotEmpty) {
          return '$city, $country';
        }
        return city.isNotEmpty ? city : country;
      }
    } catch (e) {
      debugPrint('📍 Reverse geocoding error: $e');
    }
    return 'Lokasi (${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)})';
  }

  /// Detect country code from coordinates
  static Future<String?> _getCountryCode(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        return placemarks.first.isoCountryCode;
      }
    } catch (e) {
      debugPrint('📍 Country code detection error: $e');
    }
    return null;
  }

  /// Auto-detect the best calculation method based on country
  static Future<String> autoDetectCalcMethod(double lat, double lng) async {
    final countryCode = await _getCountryCode(lat, lng);
    if (countryCode != null && _aseanCountries.contains(countryCode)) {
      return 'singapore'; // Kemenag RI / Singapore method
    }
    // Default fallback by region
    if (countryCode != null) {
      switch (countryCode) {
        case 'SA': // Saudi Arabia
        case 'AE': // UAE
        case 'QA': // Qatar
        case 'BH': // Bahrain
        case 'KW': // Kuwait
          return 'umm_al_qura';
        case 'EG': // Egypt
          return 'egyptian';
        case 'PK': // Pakistan
        case 'AF': // Afghanistan
        case 'BD': // Bangladesh
          return 'karachi';
        case 'TR': // Turkey
          return 'turkey';
        case 'IR': // Iran
          return 'tehran';
        default:
          return 'muslim_world_league';
      }
    }
    return 'muslim_world_league';
  }

  /// Auto-detect madhab based on country
  static Future<String> autoDetectMadhab(double lat, double lng) async {
    final countryCode = await _getCountryCode(lat, lng);
    if (countryCode != null && _syafiiCountries.contains(countryCode)) {
      return 'syafii';
    }
    return 'hanafi';
  }

  /// Get CalculationParameters from string method name
  static CalculationParameters _getCalcParams(String method) {
    switch (method) {
      case 'singapore':
        return CalculationMethodParameters.singapore();
      case 'muslim_world_league':
        return CalculationMethodParameters.muslimWorldLeague();
      case 'egyptian':
        return CalculationMethodParameters.egyptian();
      case 'karachi':
        return CalculationMethodParameters.karachi();
      case 'umm_al_qura':
        return CalculationMethodParameters.ummAlQura();
      case 'dubai':
        return CalculationMethodParameters.dubai();
      case 'qatar':
        return CalculationMethodParameters.qatar();
      case 'kuwait':
        return CalculationMethodParameters.kuwait();
      case 'turkey':
        return CalculationMethodParameters.turkiye();
      case 'tehran':
        return CalculationMethodParameters.tehran();
      case 'north_america':
        return CalculationMethodParameters.northAmerica();
      default:
        return CalculationMethodParameters.muslimWorldLeague();
    }
  }

  /// Calculate prayer times for a given location and date
  static DailyPrayerTimes calculatePrayerTimes({
    required double lat,
    required double lng,
    required DateTime date,
    required String locationName,
    String calcMethod = 'muslim_world_league',
    String madhab = 'syafii',
  }) {
    final coordinates = Coordinates(lat, lng);
    final params = _getCalcParams(calcMethod);
    params.madhab = madhab == 'syafii' ? Madhab.shafi : Madhab.hanafi;

    final prayerTimes = PrayerTimes(
      coordinates: coordinates,
      date: date,
      calculationParameters: params,
      precision: true,
    );

    // Calculate Imsak: 10 minutes before Fajr
    final imsak = prayerTimes.fajr!.subtract(const Duration(minutes: 10));

    // Calculate Dhuha: ~15 minutes after Sunrise
    final dhuha = prayerTimes.sunrise!.add(const Duration(minutes: 15));

    final entries = <PrayerTimeEntry>[
      PrayerTimeEntry(
        name: 'Imsak',
        arabicName: 'إمساك',
        time: imsak.toLocal(),
        isFard: false,
      ),
      PrayerTimeEntry(
        name: 'Subuh',
        arabicName: 'الفجر',
        time: prayerTimes.fajr!.toLocal(),
        isFard: true,
      ),
      PrayerTimeEntry(
        name: 'Syuruk',
        arabicName: 'الشروق',
        time: prayerTimes.sunrise!.toLocal(),
        isFard: false,
      ),
      PrayerTimeEntry(
        name: 'Dhuha',
        arabicName: 'الضحى',
        time: dhuha.toLocal(),
        isFard: false,
      ),
      PrayerTimeEntry(
        name: 'Dzuhur',
        arabicName: 'الظهر',
        time: prayerTimes.dhuhr!.toLocal(),
        isFard: true,
      ),
      PrayerTimeEntry(
        name: 'Ashar',
        arabicName: 'العصر',
        time: prayerTimes.asr!.toLocal(),
        isFard: true,
      ),
      PrayerTimeEntry(
        name: 'Maghrib',
        arabicName: 'المغرب',
        time: prayerTimes.maghrib!.toLocal(),
        isFard: true,
      ),
      PrayerTimeEntry(
        name: 'Isya',
        arabicName: 'العشاء',
        time: prayerTimes.isha!.toLocal(),
        isFard: true,
      ),
    ];

    return DailyPrayerTimes(
      entries: entries,
      locationName: locationName,
      latitude: lat,
      longitude: lng,
      date: date,
    );
  }

  // ── Persistence ────────────────────────────────────────

  static Future<bool> getUseGps() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyUseGps) ?? true;
  }

  static Future<void> setUseGps(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseGps, value);
  }

  static Future<Map<String, double>?> getSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble(_keySavedLat);
    final lng = prefs.getDouble(_keySavedLng);
    if (lat != null && lng != null) {
      return {'lat': lat, 'lng': lng};
    }
    return null;
  }

  static Future<void> saveLocation(double lat, double lng, String city) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySavedLat, lat);
    await prefs.setDouble(_keySavedLng, lng);
    await prefs.setString(_keySavedCity, city);
  }

  static Future<String?> getSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySavedCity);
  }

  static Future<String> getCalcMethod() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyCalcMethod) ?? 'muslim_world_league';
  }

  static Future<void> setCalcMethod(String method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCalcMethod, method);
  }

  static Future<String> getMadhab() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMadhab) ?? 'syafii';
  }

  static Future<void> setMadhab(String madhab) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMadhab, madhab);
  }

  /// All available calculation methods for dropdown
  static const calcMethodOptions = <String, String>{
    'singapore': 'Kemenag RI / Singapura',
    'muslim_world_league': 'Muslim World League (MWL)',
    'egyptian': 'Egyptian General Authority',
    'karachi': 'University of Karachi',
    'umm_al_qura': 'Umm al-Qura, Makkah',
    'dubai': 'Dubai',
    'qatar': 'Qatar',
    'kuwait': 'Kuwait',
    'turkey': 'Diyanet İşleri, Turki',
    'tehran': 'Institute of Geophysics, Tehran',
    'north_america': 'ISNA (Amerika Utara)',
  };

  static const madhabOptions = <String, String>{
    'syafii': 'Syafi\'i / Maliki / Hanbali',
    'hanafi': 'Hanafi',
  };
}
