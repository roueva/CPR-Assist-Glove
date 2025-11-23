import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/network_service.dart';

class AvailabilityStatus {
  final bool isOpen;
  final bool isUncertain;
  final String displayText;
  final String? detailText;
  final String originalText;

  AvailabilityStatus({
    required this.isOpen,
    required this.isUncertain,
    required this.displayText,
    this.detailText,
    required this.originalText,
  });

  /// Returns the color corresponding to the status
  Color getColor() {
    if (isUncertain) return Colors.grey;
    if (isOpen) return Colors.green;
    return Colors.red;
  }
}

class AvailabilityParser {
  static Map<String, dynamic>? _availabilityMap;

  static Future<void> loadRules() async {
    try {
      // ✅ Try to load from backend first
      final backendMap = await _fetchFromBackend();

      if (backendMap != null && backendMap.isNotEmpty) {
        _availabilityMap = backendMap;

        // Cache it locally
        await _cacheAvailabilityMap(backendMap);

        print("✅ Availability rules loaded from backend: ${_availabilityMap!.length} entries");
        return;
      }

      // ✅ Fallback to cached version
      final cachedMap = await _loadFromCache();
      if (cachedMap != null) {
        _availabilityMap = cachedMap;
        print("📦 Availability rules loaded from cache: ${_availabilityMap!.length} entries");
        return;
      }

      // ✅ Last resort: Load from bundled asset
      final jsonString = await rootBundle.loadString('assets/data/parsed_availability_map.json');
      _availabilityMap = json.decode(jsonString);
      print("📂 Availability rules loaded from asset: ${_availabilityMap!.length} entries");

    } catch (e) {
      print("❌ Error loading availability rules: $e");
      _availabilityMap = {};
    }
  }

// ✅ NEW: Fetch from backend
  static Future<Map<String, dynamic>?> _fetchFromBackend() async {
    try {
      // Use your backend URL
      final url = Uri.parse('${NetworkService.baseUrl}/aed/availability');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final count = response.headers['x-availability-count'];
        final lastUpdated = response.headers['x-last-updated'];

        print("🌐 Fetched availability rules from backend:");
        print("   → Count: $count");
        print("   → Last updated: $lastUpdated");

        return json.decode(response.body);
      }
    } catch (e) {
      print("⚠️ Could not fetch from backend: $e");
    }
    return null;
  }

// ✅ NEW: Cache the availability map
  static Future<void> _cacheAvailabilityMap(Map<String, dynamic> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_availability_map', json.encode(map));
      await prefs.setInt('availability_map_timestamp', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print("⚠️ Could not cache availability map: $e");
    }
  }

// ✅ NEW: Load from cache
  static Future<Map<String, dynamic>?> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('cached_availability_map');
      final timestamp = prefs.getInt('availability_map_timestamp');

      if (cachedData != null && timestamp != null) {
        final age = DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(timestamp)
        );

        // Use cache if less than 7 days old
        if (age.inDays < 7) {
          return json.decode(cachedData);
        }
      }
    } catch (e) {
      print("⚠️ Could not load from cache: $e");
    }
    return null;
  }

  static AvailabilityStatus parseAvailability(String? availability, {int? aedId}) {
    // 1. Handle Null/Empty/Unknown specifically at the entry point
    if (availability == null ||
        availability.trim().isEmpty ||
        availability.trim().toLowerCase() == 'unknown') {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: 'Unknown Hours',
        originalText: availability ?? '',
      );
    }

    final cleanText = availability.trim();

    if (_availabilityMap == null || !_availabilityMap!.containsKey(cleanText)) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: availability,
        originalText: availability,
      );
    }

    final data = _availabilityMap![cleanText];
    final String status = data['status'];

    // 1. Check 24/7 First (Holidays don't matter if it's 24/7)
    if (data['is_24_7'] == true) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: false,
        displayText: 'Open 24/7',
        originalText: availability,
      );
    }

    // 2. CHECK HOLIDAYS
    if (_isGreekHoliday(DateTime.now())) {
      return AvailabilityStatus(
        isOpen: false,
        isUncertain: true,
        displayText: 'Likely Closed (Holiday)',
        detailText: 'Hours may differ due to public holiday',
        originalText: availability,
      );
    }

    // 3. Check Rules (Smart Logic)
    if (data['rules'] != null && (data['rules'] as List).isNotEmpty) {
      final ruleResult = _checkRules(data['rules'], DateTime.now(), status, availability);
      if (ruleResult != null) {
        return ruleResult;
      }
    }

    // 4. Fallback Logic
    if (status == 'closed_for_use') {
      return AvailabilityStatus(
        isOpen: false,
        isUncertain: false,
        displayText: 'Private / Restricted Use',
        detailText: 'Not intended for public use',
        originalText: availability,
      );
    }

    if (status == 'uncertain') {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: 'Check Availability',
        detailText: availability,
        originalText: availability,
      );
    }

    if (status == 'parsed') {
      return AvailabilityStatus(
        isOpen: false,
        isUncertain: false,
        displayText: 'Closed',
        detailText: 'Closed at this time',
        originalText: availability,
      );
    }

    // Default
    return AvailabilityStatus(
      isOpen: true,
      isUncertain: true,
      displayText: availability,
      originalText: availability,
    );
  }

  static AvailabilityStatus? _checkRules(List<dynamic> rules, DateTime now, String generalStatus, String originalText) {
    final currentDay = now.weekday;
    final currentMonth = now.month;
    final currentTime = now.hour * 60 + now.minute;

    for (final rule in rules) {
      // Check Day
      final List<dynamic> days = rule['days'] ?? [];
      if (!days.contains(currentDay)) continue;

      // Check Season
      if (rule.containsKey('start_month') && rule.containsKey('end_month')) {
        int start = rule['start_month'];
        int end = rule['end_month'];
        int? startDay = rule['start_day'];
        int? endDay = rule['end_day'];

        bool inSeason = false;
        if (start <= end) {
          inSeason = currentMonth >= start && currentMonth <= end;
        } else {
          inSeason = currentMonth >= start || currentMonth <= end;
        }
        if (inSeason && startDay != null && currentMonth == start) {
          if (now.day < startDay) inSeason = false;
        }
        if (inSeason && endDay != null && currentMonth == end) {
          if (now.day > endDay) inSeason = false;
        }
        if (!inSeason) continue;
      }

      // Check Time
      if (rule.containsKey('open_time') && rule.containsKey('close_time')) {
        final String openTimeStr = rule['open_time'].toString();
        final String closeTimeStr = rule['close_time'].toString();

        // --- FIX START: SAFETY CHECK ---
        // If data contains "unknown" or isn't a valid time format (HH:MM), skip logic
        if (!openTimeStr.contains(':') || !closeTimeStr.contains(':')) {
          continue;
        }

        final openParts = openTimeStr.split(':');
        final closeParts = closeTimeStr.split(':');

        // Ensure we have exactly 2 parts (Hour and Minute)
        if (openParts.length < 2 || closeParts.length < 2) continue;

        // Use tryParse instead of parse to prevent crashing
        final int? openHour = int.tryParse(openParts[0]);
        final int? openMinute = int.tryParse(openParts[1]);
        final int? closeHour = int.tryParse(closeParts[0]);
        final int? closeMinute = int.tryParse(closeParts[1]);

        if (openHour == null || openMinute == null || closeHour == null || closeMinute == null) {
          continue; // Invalid numbers found
        }

        final openMins = openHour * 60 + openMinute;
        int closeMins = closeHour * 60 + closeMinute;
        // --- FIX END ---

        bool isOpenNow = false;

        if (closeMins <= openMins && closeMins != 0) {
          bool isLateNight = currentTime >= openMins;
          bool isEarlyMorning = currentTime < closeMins;
          if (isLateNight || isEarlyMorning) isOpenNow = true;
        } else {
          if (closeMins == 0) closeMins = 24 * 60;
          if (currentTime >= openMins && currentTime < closeMins) isOpenNow = true;
        }

        if (isOpenNow) {
          return AvailabilityStatus(
            isOpen: true,
            isUncertain: false,
            displayText: 'Open Now',
            detailText: 'Closes at ${rule['close_time']}',
            originalText: originalText,
          );
        }
      } else {
        // Rule exists but no time -> Uncertain fallback
        if (generalStatus == 'uncertain') {
          return AvailabilityStatus(
            isOpen: true,
            isUncertain: true,
            displayText: 'Check Availability',
            detailText: originalText,
            originalText: originalText,
          );
        }
      }
    }
    return null;
  }

  // --- HOLIDAY LOGIC ---

  static bool _isGreekHoliday(DateTime date) {
    final int year = date.year;
    final int month = date.month;
    final int day = date.day;

    // 1. Fixed Holidays
    if (month == 1 && day == 1) return true;   // New Year
    if (month == 1 && day == 6) return true;   // Epiphany
    if (month == 3 && day == 25) return true;  // Annunciation
    if (month == 5 && day == 1) return true;   // Labor Day
    if (month == 8 && day == 15) return true;  // Assumption
    if (month == 10 && day == 28) return true; // Ochi Day
    if (month == 12 && day == 25) return true; // Christmas
    if (month == 12 && day == 26) return true; // Boxing Day

    // 2. Movable Holidays (Based on Orthodox Easter)
    final DateTime easter = _calculateOrthodoxEaster(year);

    // Clean Monday - 48 days before Easter
    final DateTime cleanMonday = easter.subtract(const Duration(days: 48));
    if (month == cleanMonday.month && day == cleanMonday.day) return true;

    // Good Friday - 2 days before Easter
    final DateTime goodFriday = easter.subtract(const Duration(days: 2));
    if (month == goodFriday.month && day == goodFriday.day) return true;

    // Easter Sunday
    if (month == easter.month && day == easter.day) return true;

    // Easter Monday - 1 day after Easter
    final DateTime easterMonday = easter.add(const Duration(days: 1));
    if (month == easterMonday.month && day == easterMonday.day) return true;

    // Holy Spirit - 50 days after Easter
    final DateTime holySpirit = easter.add(const Duration(days: 50));
    if (month == holySpirit.month && day == holySpirit.day) return true;

    return false;
  }

  /// Calculates Orthodox Easter date using the Meeus/Jones/Butcher algorithm
  static DateTime _calculateOrthodoxEaster(int year) {
    final int r1 = year % 19;
    final int r2 = year % 4;
    final int r3 = year % 7;
    final int ra = 19 * r1 + 16;
    final int r4 = ra % 30;
    final int rb = 2 * r2 + 4 * r3 + 6 * r4;
    final int r5 = rb % 7;
    final int rc = 3 + r4 + r5;

    DateTime date;
    if (rc <= 30) {
      date = DateTime(year, 4, rc); // April
    } else {
      date = DateTime(year, 5, rc - 30); // May
    }
    return date;
  }
}