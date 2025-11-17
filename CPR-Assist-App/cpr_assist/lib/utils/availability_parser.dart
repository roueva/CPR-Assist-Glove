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
  /// Parse Greek availability text and determine current status
  static AvailabilityStatus parseAvailability(String? availability) {
    if (availability == null || availability.isEmpty) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: 'Hours unknown',
      );
    }

    final now = DateTime.now();
    final currentHour = now.hour;
    final currentDay = now.weekday; // 1 = Monday, 7 = Sunday

    // Normalize text for comparison
    final text = availability.toLowerCase().trim();

    // 1. "Όλο τον χρόνο" = Always available (24/7)
    if (text.contains('όλο τον χρόνο') ||
        text.contains('24/7') ||
        text.contains('πάντα')) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: false,
        displayText: 'Open 24 hours',
      );
    }

    // 2. "Μόνο το καλοκαίρι" = Summer only (May-September)
    if (text.contains('καλοκαίρι') ||
        text.contains('τουριστική περίοδος')) {
      final isSummer = now.month >= 5 && now.month <= 9;
      return AvailabilityStatus(
        isOpen: isSummer,
        isUncertain: false,
        displayText: isSummer ? 'Open (seasonal)' : 'Closed (seasonal)',
        detailText: 'Summer only',
      );
    }

    // 3. Parse specific day/time patterns like "Δευτέρα έως Παρασκευή 7:00 - 16:00"
    final specificHours = _parseSpecificHours(availability, now);
    if (specificHours != null) {
      return specificHours;
    }

    // 4. "Ωράριο λειτουργίας Σχολείων" = School hours
    if (text.contains('σχολείων') || text.contains('σχολείου')) {
      final isWeekday = currentDay >= 1 && currentDay <= 5;
      final isSchoolHours = currentHour >= 8 && currentHour < 14;

      if (isWeekday && isSchoolHours) {
        return AvailabilityStatus(
          isOpen: true,
          isUncertain: false,
          displayText: 'Open now',
          detailText: 'School hours',
        );
      } else if (isWeekday) {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: 'Opens at 8:00 AM',
        );
      } else {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: 'Weekends',
        );
      }
    }

    // 5. "Ωράριο λειτουργίας Υπηρεσιών" = Service/Office hours
    if (text.contains('υπηρεσιών') || text.contains('γραφείων')) {
      final isWeekday = currentDay >= 1 && currentDay <= 5;
      final isOfficeHours = currentHour >= 8 && currentHour < 16;

      if (isWeekday && isOfficeHours) {
        return AvailabilityStatus(
          isOpen: true,
          isUncertain: false,
          displayText: 'Open now',
          detailText: 'Office hours',
        );
      } else if (isWeekday) {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: 'Opens at 8:00 AM',
        );
      } else {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: 'Weekends',
        );
      }
    }

    // 6. "Ωράριο λειτουργίας καταστημάτων" = Store hours
    if (text.contains('καταστημάτων') || text.contains('καταστήματος')) {
      final isWeekday = currentDay >= 1 && currentDay <= 6;
      final isStoreHours = currentHour >= 9 && currentHour < 21;

      if (isWeekday && isStoreHours) {
        return AvailabilityStatus(
          isOpen: true,
          isUncertain: false,
          displayText: 'Open now',
          detailText: 'Store hours',
        );
      } else if (isWeekday) {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: currentHour < 9 ? 'Opens at 9:00 AM' : 'Closed for today',
        );
      } else {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: 'Sundays',
        );
      }
    }

    // 7. Unknown format - show the original text as uncertain
    return AvailabilityStatus(
      isOpen: true,
      isUncertain: true,
      displayText: availability,
    );
  }

  /// ✅ NEW: Parse specific hours like "Δευτέρα έως Παρασκευή 7:00 - 16:00"
  static AvailabilityStatus? _parseSpecificHours(String text, DateTime now) {
    final lowerText = text.toLowerCase();

    // Greek day names
    final dayMap = {
      'δευτέρα': 1,
      'τρίτη': 2,
      'τετάρτη': 3,
      'πέμπτη': 4,
      'παρασκευή': 5,
      'σάββατο': 6,
      'κυριακή': 7,
    };

    // Try to match pattern: "Day έως Day HH:MM - HH:MM"
    int? startDay;
    int? endDay;
    int? openHour;
    int? openMinute;
    int? closeHour;
    int? closeMinute;

    // Find day range
    for (final entry in dayMap.entries) {
      if (lowerText.contains(entry.key)) {
        if (startDay == null) {
          startDay = entry.value;
        } else {
          endDay ??= entry.value;
        }
      }
    }

    // If we found "έως" (to), we have a range
    if (lowerText.contains('έως') && startDay != null && endDay != null) {
      // Good, we have day range
    } else if (startDay != null && endDay == null) {
      // Single day mentioned, assume same day
      endDay = startDay;
    }

    // Try to parse time: "7:00 - 16:00" or "07:00-16:00"
    final timePattern = RegExp(r'(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})');
    final timeMatch = timePattern.firstMatch(text);

    if (timeMatch != null) {
      openHour = int.tryParse(timeMatch.group(1)!);
      openMinute = int.tryParse(timeMatch.group(2)!);
      closeHour = int.tryParse(timeMatch.group(3)!);
      closeMinute = int.tryParse(timeMatch.group(4)!);
    }

    // If we successfully parsed everything, check current time
    if (startDay != null && endDay != null && openHour != null && closeHour != null) {
      final currentDay = now.weekday;
      final currentMinutes = now.hour * 60 + now.minute;
      final openMinutes = openHour * 60 + (openMinute ?? 0);
      final closeMinutes = closeHour * 60 + (closeMinute ?? 0);

      // Check if current day is in range
      final isInDayRange = currentDay >= startDay && currentDay <= endDay;
      final isInTimeRange = currentMinutes >= openMinutes && currentMinutes < closeMinutes;

      if (isInDayRange && isInTimeRange) {
        return AvailabilityStatus(
          isOpen: true,
          isUncertain: false,
          displayText: 'Open now',
          detailText: 'Closes at $closeHour:${closeMinute?.toString().padLeft(2, '0') ?? '00'}',
        );
      } else if (isInDayRange) {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: 'Opens at $openHour:${openMinute?.toString().padLeft(2, '0') ?? '00'}',
        );
      } else {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: _getDayName(startDay),
        );
      }
    }

    return null; // Couldn't parse
  }

  static String _getDayName(int day) {
    switch (day) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Weekdays';
    }
  }
}