import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cpr_assist/core/core.dart';
import '../../../services/network/network_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AvailabilityStatus
// ─────────────────────────────────────────────────────────────────────────────

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

  /// Semantic color mapped from AppColors — never use Colors.xxx directly.
  Color getColor() {
    if (isUncertain) return AppColors.textDisabled;
    if (isOpen)      return AppColors.success;
    return AppColors.error;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AvailabilityParser
// ─────────────────────────────────────────────────────────────────────────────

class AvailabilityParser {
  static Map<String, dynamic>? _availabilityMap;

  // ── Load rules ─────────────────────────────────────────────────────────────

  static Future<void> loadRules() async {
    try {
      // 1. Try backend first
      final backendMap = await _fetchFromBackend();
      if (backendMap != null && backendMap.isNotEmpty) {
        _availabilityMap = backendMap;
        await _cacheAvailabilityMap(backendMap);
        return;
      }

      // 2. Fallback to cache
      final cachedMap = await _loadFromCache();
      if (cachedMap != null && cachedMap.isNotEmpty) {
        _availabilityMap = cachedMap;
        return;
      }

      // 3. Last resort: bundled asset
      final jsonString = await rootBundle
          .loadString('assets/data/parsed_availability_map.json');
      final assetMap = json.decode(jsonString) as Map<String, dynamic>?;

      if (assetMap != null && assetMap.isNotEmpty) {
        _availabilityMap = assetMap;
      } else {
        _availabilityMap = null;
      }
    } catch (_) {
      _availabilityMap = null;
    }
  }

  /// Returns true if availability parsing is available.
  static bool isAvailable() =>
      _availabilityMap != null && _availabilityMap!.isNotEmpty;

  // ── Backend fetch ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _fetchFromBackend() async {
    try {
      final url = Uri.parse('${NetworkService.baseUrl}/aed/availability');
      final response = await http
          .get(url)
          .timeout(AppConstants.apiTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      // Network unavailable — fall through to cache
    }
    return null;
  }

  // ── Cache ───────────────────────────────────────────────────────────────────

  static Future<void> _cacheAvailabilityMap(
      Map<String, dynamic> map) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_availability_map', json.encode(map));
      await prefs.setInt(
        'availability_map_timestamp',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Non-fatal — app continues without caching
    }
  }

  static Future<Map<String, dynamic>?> _loadFromCache() async {
    try {
      final prefs     = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('cached_availability_map');
      final timestamp  = prefs.getInt('availability_map_timestamp');

      if (cachedData != null && timestamp != null) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(timestamp),
        );
        if (age.inDays < 7) {
          return json.decode(cachedData) as Map<String, dynamic>;
        }
      }
    } catch (_) {
      // Non-fatal
    }
    return null;
  }

  // ── Parse ───────────────────────────────────────────────────────────────────

  static AvailabilityStatus parseAvailability(
      String? availability, {
        int? aedId,
      }) {
    // No availability data loaded — signal UI to hide the section
    if (_availabilityMap == null) {
      return AvailabilityStatus(
        isOpen:      false,
        isUncertain: true,
        displayText: '',
        originalText: '',
      );
    }

    // Null / empty / unknown
    if (availability == null ||
        availability.trim().isEmpty ||
        availability.trim().toLowerCase() == 'unknown') {
      return AvailabilityStatus(
        isOpen:      false,
        isUncertain: true,
        displayText: '',
        originalText: availability ?? '',
      );
    }

    final cleanText = availability.trim();

    // Not in map — show raw text, uncertain
    if (!_availabilityMap!.containsKey(cleanText)) {
      return AvailabilityStatus(
        isOpen:      true,
        isUncertain: true,
        displayText: availability,
        originalText: availability,
      );
    }

    final data         = _availabilityMap![cleanText] as Map<String, dynamic>;
    final String status = data['status'] as String;

    // 1. 24/7
    if (data['is_24_7'] == true) {
      return AvailabilityStatus(
        isOpen:      true,
        isUncertain: false,
        displayText: 'Open 24/7',
        originalText: availability,
      );
    }

    // 2. Holiday
    if (_isGreekHoliday(DateTime.now())) {
      return AvailabilityStatus(
        isOpen:      false,
        isUncertain: true,
        displayText: 'Likely Closed (Holiday)',
        detailText:  'Hours may differ due to public holiday',
        originalText: availability,
      );
    }

    // 3. Rule-based check
    if (data['rules'] != null &&
        (data['rules'] as List).isNotEmpty) {
      final ruleResult = _checkRules(
        data['rules'] as List<dynamic>,
        DateTime.now(),
        status,
        availability,
      );
      if (ruleResult != null) return ruleResult;
    }

    // 4. Fallback by status
    if (status == 'closed_for_use') {
      return AvailabilityStatus(
        isOpen:      false,
        isUncertain: false,
        displayText: 'Private / Restricted Use',
        detailText:  'Not intended for public use',
        originalText: availability,
      );
    }

    if (status == 'uncertain') {
      return AvailabilityStatus(
        isOpen:      true,
        isUncertain: true,
        displayText: 'Check Availability',
        detailText:  availability,
        originalText: availability,
      );
    }

    if (status == 'parsed') {
      return AvailabilityStatus(
        isOpen:      false,
        isUncertain: false,
        displayText: 'Closed',
        detailText:  'Closed at this time',
        originalText: availability,
      );
    }

    // Default
    return AvailabilityStatus(
      isOpen:      true,
      isUncertain: true,
      displayText: availability,
      originalText: availability,
    );
  }

  // ── Rule engine ─────────────────────────────────────────────────────────────

  static AvailabilityStatus? _checkRules(
      List<dynamic> rules,
      DateTime now,
      String generalStatus,
      String originalText,
      ) {
    final currentDay   = now.weekday;
    final currentMonth = now.month;
    final currentTime  = now.hour * 60 + now.minute;

    for (final rule in rules) {
      // Day check
      final List<dynamic> days = rule['days'] as List<dynamic>? ?? [];
      if (!days.contains(currentDay)) continue;

      // Season check
      if (rule['start_month'] != null && rule['end_month'] != null) {
        final int start    = rule['start_month'] as int;
        final int end      = rule['end_month']   as int;
        final int? startDay = rule['start_day']  as int?;
        final int? endDay   = rule['end_day']    as int?;

        bool inSeason = start <= end
            ? currentMonth >= start && currentMonth <= end
            : currentMonth >= start || currentMonth <= end;

        if (inSeason && startDay != null && currentMonth == start) {
          if (now.day < startDay) inSeason = false;
        }
        if (inSeason && endDay != null && currentMonth == end) {
          if (now.day > endDay) inSeason = false;
        }
        if (!inSeason) continue;
      }

      // Time check
      if (rule['open_time'] != null && rule['close_time'] != null) {
        final openTimeStr  = rule['open_time'].toString();
        final closeTimeStr = rule['close_time'].toString();

        if (!openTimeStr.contains(':') || !closeTimeStr.contains(':')) continue;

        final openParts  = openTimeStr.split(':');
        final closeParts = closeTimeStr.split(':');

        if (openParts.length < 2 || closeParts.length < 2) continue;

        final int? openHour    = int.tryParse(openParts[0]);
        final int? openMinute  = int.tryParse(openParts[1]);
        final int? closeHour   = int.tryParse(closeParts[0]);
        final int? closeMinute = int.tryParse(closeParts[1]);

        if (openHour   == null || openMinute  == null ||
            closeHour  == null || closeMinute == null) {
          continue;
        }

        final openMins  = openHour  * 60 + openMinute;
        int   closeMins = closeHour * 60 + closeMinute;

        bool isOpenNow = false;
        if (closeMins <= openMins && closeMins != 0) {
          isOpenNow =
              currentTime >= openMins || currentTime < closeMins;
        } else {
          if (closeMins == 0) closeMins = 24 * 60;
          isOpenNow =
              currentTime >= openMins && currentTime < closeMins;
        }

        if (isOpenNow) {
          return AvailabilityStatus(
            isOpen:      true,
            isUncertain: false,
            displayText: 'Open Now',
            detailText:  'Closes at ${rule['close_time']}',
            originalText: originalText,
          );
        }
      } else {
        // Rule exists but no time → uncertain fallback
        if (generalStatus == 'uncertain') {
          return AvailabilityStatus(
            isOpen:      true,
            isUncertain: true,
            displayText: 'Check Availability',
            detailText:  originalText,
            originalText: originalText,
          );
        }
      }
    }
    return null;
  }

  // ── Holiday logic ───────────────────────────────────────────────────────────

  static bool _isGreekHoliday(DateTime date) {
    final int month = date.month;
    final int day   = date.day;

    // Fixed holidays
    if (month == 1  && day == 1)  return true; // New Year
    if (month == 1  && day == 6)  return true; // Epiphany
    if (month == 3  && day == 25) return true; // Annunciation
    if (month == 5  && day == 1)  return true; // Labour Day
    if (month == 8  && day == 15) return true; // Assumption
    if (month == 10 && day == 28) return true; // Ochi Day
    if (month == 12 && day == 25) return true; // Christmas
    if (month == 12 && day == 26) return true; // Second Day of Christmas

    // Movable Orthodox holidays
    final easter      = _calculateOrthodoxEaster(date.year);
    final cleanMonday = easter.subtract(const Duration(days: 48));
    final goodFriday  = easter.subtract(const Duration(days: 2));
    final easterMonday = easter.add(const Duration(days: 1));
    final holySpirit  = easter.add(const Duration(days: 50));

    for (final holiday in [
      cleanMonday, goodFriday, easter, easterMonday, holySpirit,
    ]) {
      if (month == holiday.month && day == holiday.day) return true;
    }

    return false;
  }

  /// Orthodox Easter via the Meeus/Jones/Butcher algorithm.
  static DateTime _calculateOrthodoxEaster(int year) {
    final r1 = year % 19;
    final r2 = year % 4;
    final r3 = year % 7;
    final r4 = (19 * r1 + 16) % 30;
    final r5 = (2 * r2 + 4 * r3 + 6 * r4) % 7;
    final rc = 3 + r4 + r5;

    return rc <= 30
        ? DateTime(year, 4, rc)
        : DateTime(year, 5, rc - 30);
  }
}