import 'dart:convert';
import 'package:flutter/services.dart'; // For rootBundle

class AvailabilityStatus {
  final bool isOpen;
  final bool isUncertain;
  final String displayText;
  final String? detailText;

  AvailabilityStatus({
    required this.isOpen,
    required this.isUncertain,
    required this.displayText,
    this.detailText,
  });
}

class AvailabilityParser {
  static Map<String, dynamic>? _availabilityMap;

  /// Initialize this once when your app starts (e.g. in main.dart)
  static Future<void> loadRules() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/parsed_availability_map.json');
      _availabilityMap = json.decode(jsonString);
      print("✅ Availability rules loaded successfully.");
    } catch (e) {
      print("❌ Error loading availability rules: $e");
      _availabilityMap = {}; // Empty map fallback
    }
  }

  static AvailabilityStatus parseAvailability(String? availability) {
    if (availability == null || availability.trim().isEmpty) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: 'Άγνωστο Ωράριο', // Unknown Hours
      );
    }

    final cleanText = availability.trim();

    // 1. Look up the string in our loaded JSON map
    // If the map isn't loaded or the string is new/missing, fallback to default
    if (_availabilityMap == null || !_availabilityMap!.containsKey(cleanText)) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: availability,
      );
    }

    final data = _availabilityMap![cleanText];
    final String status = data['status'];

    // 2. Check for 24/7 first (Explicit open)
    if (data['is_24_7'] == true) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: false,
        displayText: 'Ανοιχτό 24/7',
      );
    }

    // 3. Try to check RULES first (Smart Logic)
    // This allows us to handle "Hybrid" cases (Specific hours on Weekdays, Uncertain on Weekends)
    if (data['rules'] != null && (data['rules'] as List).isNotEmpty) {
      final ruleResult = _checkRules(data['rules'], DateTime.now(), status, availability);
      if (ruleResult != null) {
        return ruleResult;
      }
      // If _checkRules returns null, it means no specific rule matched "Open" or "Uncertain" for NOW.
      // We proceed to fallback logic.
    }

    // 4. Fallback: Handle general statuses if no rule matched
    if (status == 'closed_for_use') {
      return AvailabilityStatus(
        isOpen: false,
        isUncertain: false,
        displayText: 'Ιδιωτική / Περιορισμένη Χρήση',
        detailText: availability,
      );
    }

    if (status == 'uncertain') {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: 'Ελέγξτε Διαθεσιμότητα',
        detailText: availability,
      );
    }

    // Default fallback
    return AvailabilityStatus(
      isOpen: true,
      isUncertain: true,
      displayText: availability,
    );
  }

  static AvailabilityStatus? _checkRules(List<dynamic> rules, DateTime now, String generalStatus, String originalText) {
    final currentDay = now.weekday; // 1 = Mon, 7 = Sun
    final currentMonth = now.month;
    final currentTime = now.hour * 60 + now.minute;

    for (final rule in rules) {
      // --- A. Check Day of Week ---
      final List<dynamic> days = rule['days'] ?? [];
      if (!days.contains(currentDay)) {
        continue; // This rule doesn't apply to today
      }

      // --- B. Check Season/Month (Optional) ---
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

        // Refined logic for specific start/end days (e.g., June 15)
        if (inSeason && startDay != null && currentMonth == start) {
          if (now.day < startDay) inSeason = false;
        }
        if (inSeason && endDay != null && currentMonth == end) {
          if (now.day > endDay) inSeason = false;
        }

        if (!inSeason) continue; // Wrong season
      }

      // --- C. Check Time ---
      if (rule.containsKey('open_time') && rule.containsKey('close_time')) {
        final openParts = rule['open_time'].split(':');
        final closeParts = rule['close_time'].split(':');

        final openMins = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
        int closeMins = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);

        if (closeMins <= openMins && closeMins != 0) {
          // Overnight logic (e.g. 20:00 - 04:00)
          bool isLateNight = currentTime >= openMins;
          bool isEarlyMorning = currentTime < closeMins;

          if (isLateNight || isEarlyMorning) {
            return AvailabilityStatus(
              isOpen: true,
              isUncertain: false,
              displayText: 'Ανοιχτό Τώρα',
              detailText: 'Κλείνει στις ${rule['close_time']}',
            );
          }
        } else {
          // Standard day logic (e.g. 09:00 - 17:00)
          if (closeMins == 0) closeMins = 24 * 60;

          if (currentTime >= openMins && currentTime < closeMins) {
            return AvailabilityStatus(
              isOpen: true,
              isUncertain: false,
              displayText: 'Ανοιχτό Τώρα',
              detailText: 'Κλείνει στις ${rule['close_time']}',
            );
          }
        }
      } else {
        // --- D. SPECIAL CASE: Rule matches day, but NO times specified ---
        // Example: "Weekend during games". The rule exists for Saturday, but has no hours.
        // In this case, we check the general status.

        if (generalStatus == 'uncertain') {
          return AvailabilityStatus(
            isOpen: true,
            isUncertain: true, // It matches the day, but we don't know the time
            displayText: 'Ελέγξτε Διαθεσιμότητα',
            detailText: originalText,
          );
        }
      }
    }

    // If we found a rule for today (e.g. it's Monday) but the time didn't match (it's 10 PM and closes at 5 PM):
    // We return CLOSED.

    // However, if we found NO rule for today at all (e.g. it's Sunday and rules are only Mon-Fri),
    // we also return CLOSED.

    return AvailabilityStatus(
      isOpen: false,
      isUncertain: false,
      displayText: 'Κλειστό',
      detailText: 'Κλειστό αυτή την ώρα',
    );
  }
}