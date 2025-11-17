import 'dart:developer';

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
  // A helper map for parsing Greek month names
  static const Map<String, int> _monthMap = {
    'ιανουαρίου': 1,
    'φεβρουαρίου': 2,
    'μαρτίου': 3,
    'απριλίου': 4,
    'μαΐου': 5,
    'μαίου': 5,
    'ιουνίου': 6,
    'ιουλίου': 7,
    'αυγούστου': 8,
    'σεπτεμβρίου': 9,
    'οκτωβρίου': 10,
    'νοεμβρίου': 11,
    'δεκεμβρίου': 12,
    'ιανουάριο': 1,
    'φεβρουάριο': 2,
    'μάρτιο': 3,
    'απρίλιο': 4,
    'μάϊο': 5,
    'μάιο': 5,
    'ιούνιο': 6,
    'ιούλιο': 7,
    'αύγουστο': 8,
    'σεπτέμβριο': 9,
    'οκτώβριο': 10,
    'νοέμβριο': 11,
    'δεκέμβριο': 12,
  };

  /// Parse Greek availability text and determine current status
  static AvailabilityStatus parseAvailability(String? availability, {
    int? aedId, // 👈 ADD aedId for logging
    }) {
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
    final currentMonth = now.month;

    // Normalize text for comparison
    final text = availability.toLowerCase().trim();

    // === RULE 1: 24/7 ===
    if (text.contains('όλο τον χρόνο') ||
        text.contains('24/7') ||
        text.contains('πάντα') ||
        text.contains('24ώρο')) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: false,
        displayText: 'Open 24 hours',
      );
    }

    // === RULE 2: "For Actions Only" (Closed to public) ===
    if (text.contains('μόνο για τις δράσεις') ||
        text.contains('κάλυπτει ανάγκες της διασωστικής ομάδας') ||
        text.contains('εθελοντικές δράσεις')) {
      return AvailabilityStatus(
        isOpen: false,
        isUncertain: false,
        displayText: 'For Rescue Team Use Only',
      );
    }

    // === RULE 3: "By Phone" (Uncertain) ===
    if (text.contains('τηλεφωνικής επικοινωνίας') ||
        text.contains('τηλέφωνο') ||
        text.contains('κατόπιν συνεννοήσεως') ||
        text.contains('επκοινωνία με τους υπεύθυνους')) {
      return AvailabilityStatus(
        isOpen: true, // It's *potentially* available
        isUncertain: true,
        displayText: 'By Phone Contact',
      );
    }

    // === RULE 4: "During Events" (Uncertain) ===
    if (text.contains('αγώνες') || // Games
        text.contains('αγωνιστικές') || // Game-related
        text.contains('προπονήσεις') || // Practices
        text.contains('αθλητικές δραστηριότητες') ||
        text.contains('αθλητικού συλλόγου') ||
        text.contains('γηπέδου') || // Stadium
        text.contains('σταδίου') || // Stadium
        text.contains('γυμναστηρίου') || // Gym
        text.contains('ακαδημίας')) { // Academy
      return AvailabilityStatus(
        isOpen: true, // Potentially open
        isUncertain: true,
        displayText: 'During Games/Practices',
      );
    }

    // === RULE 5: "Bank Hours" ===
    if (text.contains('τράπεζας') || text.contains('τραπέζης')) {
      final isWeekday = currentDay >= 1 && currentDay <= 5;
      final isBankHours = currentHour >= 8 &&
          currentMinutes(now) < (14 * 60 + 30); // 8:00 - 14:30

      if (isWeekday && isBankHours) {
        return AvailabilityStatus(
          isOpen: true,
          isUncertain: false,
          displayText: 'Open now',
          detailText: 'Bank hours',
        );
      } else {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: 'Bank hours',
        );
      }
    }

    // === RULE 6: "Airport Hours" (Uncertain) ===
    if (text.contains('αεροδρομίου') || text.contains('πτήσεων')) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: 'Airport/Flight Hours',
      );
    }

    // === RULE 7: "Until Sunset" (Uncertain) ===
    if (text.contains('δύση του ηλίου')) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: true,
        displayText: 'Until Sunset',
      );
    }

    // === RULE 8: "School Hours" ===
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

    // === RULE 9: "Office Hours" ===
    if (text.contains('υπηρεσιών') || text.contains('γραφείων') ||
        text.contains('ιατρείου')) {
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

    // === RULE 10: "Store Hours" ===
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

    // === RULE 11: Complex Seasonal (AED 3483) ===
    if (text.startsWith('καθημερινά: από 1μαίου έως 10 σεπτεμβρίου:')) {
      try {
        final isSummer = currentMonth >= 5 && (currentMonth < 9 ||
            (currentMonth == 9 && now.day <= 10)); // May 1 - Sep 10
        if (isSummer) {
          // (06:00-15:00 & 15:30-22:00)
          final r1 = _checkTime(now, 6, 0, 15, 0, "");
          if (r1.isOpen) return r1.copyWith(detailText: "Summer Season");
          final r2 = _checkTime(now, 15, 30, 22, 0, "");
          if (r2.isOpen) return r2.copyWith(detailText: "Summer Season");
          return AvailabilityStatus(isOpen: false,
              isUncertain: false,
              displayText: "Closed",
              detailText: "Opens 06:00 (Summer)");
        } else {
          // Winter: (06:00-20:15)
          return _checkTime(now, 6, 0, 20, 15, "Winter Season");
        }
      } catch (e) {
        /* Fall through */
      }
    }

    // === RULE 12: Complex Seasonal (AED 277) ===
    if (text.startsWith('περίοδος λειτουργίας έως 15 ιουνίου')) {
      try {
        if (currentMonth < 6 ||
            (currentMonth == 6 && now.day <= 15)) { // Until June 15
          return _checkTime(now, 10, 0, 18, 0, "Season 1");
        } else if (currentMonth <= 8) { // June 16 - Aug 31
          return _checkTime(now, 10, 0, 19, 0, "Season 2 (Summer)");
        } else { // From Sep 1
          return _checkTime(now, 10, 0, 18, 0, "Season 3");
        }
      } catch (e) {
        /* Fall through */
      }
    }

    // === RULE 13: Complex Seasonal "01/05-31/10... 24ωρο, ... 01/11-30/04... 09:00-17:00" (Handles 13366, 13365) ===
    if (text.contains('01/05-31/10') && text.contains('01/11-30/04')) {
      final isSummer = currentMonth >= 5 && currentMonth <= 10;
      if (isSummer) {
        if (text.contains('24ωρο')) {
          return AvailabilityStatus(isOpen: true,
              isUncertain: false,
              displayText: 'Open 24 hours',
              detailText: 'Summer Season');
        }
      } else {
        // Winter part: 09:00-17:00
        return _checkTime(now, 9, 0, 17, 0, "Winter Season");
      }
    }

    // === RULE 14: Complex Seasonal "Ιούλιο έως Σεπτέμβριο... Οκτώβριο έως Μάιο..." (Handles 2263, 2262) ===
    if ((text.contains('ιούλιο έως σεπτέμβριο') ||
        text.contains('ιούλιος -μάιος')) &&
        text.contains('οκτώβριο έως μάιο')) {
      try {
        final summerMatch = RegExp(
            r'(?:ιούλιο έως σεπτέμβριο|ιούλιος -μάιος)\s*\((\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})\)')
            .firstMatch(text);
        final winterMatch = RegExp(
            r'οκτώβριο έως μάιο\s*\((\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})\)')
            .firstMatch(text);

        if (summerMatch != null && winterMatch != null) {
          final isSummer = currentMonth >= 7 && currentMonth <= 9; // Jul-Sep
          if (isSummer) {
            final oh = int.parse(summerMatch.group(1)!);
            final om = int.parse(summerMatch.group(2)!);
            final ch = int.parse(summerMatch.group(3)!);
            final cm = int.parse(summerMatch.group(4)!);
            return _checkTime(now, oh, om, ch, cm, "Summer (Jul-Sep)");
          } else {
            final oh = int.parse(winterMatch.group(1)!);
            final om = int.parse(winterMatch.group(2)!);
            final ch = int.parse(winterMatch.group(3)!);
            final cm = int.parse(winterMatch.group(4)!);
            return _checkTime(now, oh, om, ch, cm, "Winter (Oct-May)");
          }
        }
      } catch (e) {
        /* Fall through */
      }
    }

    // === RULE 15: Weekday/Seasonal Hybrid "Δευτέρα έως Παρασκευή... (Αύγουστο έως Μάιο)..." (Handles 2260, 2259) ===
    if (text.contains('δευτέρα έως παρασκευή') &&
        (text.contains('αύγουστο έως μάιο') ||
            text.contains('ιούλιος -μάιος'))) {
      try {
        final match = RegExp(
            r'\((\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})\)').firstMatch(
            text);
        if (match != null) {
          final isSeason = currentMonth >= 8 || currentMonth <= 5; // Aug-May
          final isWeekday = currentDay >= 1 && currentDay <= 5;
          if (isSeason && isWeekday) {
            final oh = int.parse(match.group(1)!);
            final om = int.parse(match.group(2)!);
            final ch = int.parse(match.group(3)!);
            final cm = int.parse(match.group(4)!);
            return _checkTime(now, oh, om, ch, cm, "Weekdays (Aug-May)");
          }
          return AvailabilityStatus(isOpen: false,
              isUncertain: false,
              displayText: 'Closed',
              detailText: 'Weekdays (Aug-May)');
        }
      } catch (e) {
        /* Fall through */
      }
    }

    // === RULE 16: Seasonal rule "Καλοκαιρινή περίοδο... Χειμερινη περίοδο..." (Handles 2253, 10916, 3993, 806) ===
    try {
      final summerMatch = RegExp(
          r'καλοκαιρινή περίοδο\s*:\s*.*?\((\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})\)')
          .firstMatch(text);
      final winterMatch = RegExp(
          r'χειμερινη περίοδο\s*:\s*.*?\((\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})\)')
          .firstMatch(text);

      if (summerMatch != null && winterMatch != null) {
        final isSummer = currentMonth >= 5 &&
            currentMonth <= 9; // Define summer as May-Sept
        final match = isSummer ? summerMatch : winterMatch;
        final seasonText = isSummer ? "Summer" : "Winter";

        final oh = int.parse(match.group(1)!);
        final om = int.parse(match.group(2)!);
        final ch = int.parse(match.group(3)!);
        final cm = int.parse(match.group(4)!);

        return _checkTime(now, oh, om, ch, cm, "$seasonText hours");
      }
    } catch (e) {
      /* Fall through */
    }

    // === RULE 17: Seasonal "Είναι προσβάσιμος από 1/5 εώς 1/10" (Handles 540, 541, 423)
    if (text.startsWith('είναι προσβάσιμος από 1/5 εώς 1/10')) {
      final isSeason = currentMonth >= 5 && currentMonth <= 10;
      return AvailabilityStatus(
        isOpen: isSeason,
        isUncertain: true, // No times given
        displayText: isSeason ? 'Open (Seasonal)' : 'Closed (Seasonal)',
        detailText: 'May 1 - Oct 10',
      );
    }

    // === RULE 18: Seasonal "Από [Date] έως [Date]... (HH:MM - HH:MM)" (Handles 3096, 3085, etc.) ===
    try {
      // Catches "Από 1 Ιουνίου έως 30 Σεπτεμβρίου, Ώρες: (10:00 - 18:00)"
      final dateMatch = RegExp(
          r'από\s*(\d{1,2})\s*(\w+)\s*έως\s*(\d{1,2})\s*(\w+).*?\((\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})\)')
          .firstMatch(text);
      if (dateMatch != null) {
        final startDay = int.parse(dateMatch.group(1)!);
        final startMonth = _monthMap[dateMatch.group(2)!];
        final endDay = int.parse(dateMatch.group(3)!);
        final endMonth = _monthMap[dateMatch.group(4)!];

        final oh = int.parse(dateMatch.group(5)!);
        final om = int.parse(dateMatch.group(6)!);
        final ch = int.parse(dateMatch.group(7)!);
        final cm = int.parse(dateMatch.group(8)!);

        if (startMonth != null && endMonth != null) {
          final isAfterStart = currentMonth > startMonth ||
              (currentMonth == startMonth && now.day >= startDay);
          final isBeforeEnd = currentMonth < endMonth ||
              (currentMonth == endMonth && now.day <= endDay);

          if (isAfterStart && isBeforeEnd) {
            return _checkTime(now, oh, om, ch, cm, "Seasonal");
          } else {
            return AvailabilityStatus(isOpen: false,
                isUncertain: false,
                displayText: "Closed (Seasonal)",
                detailText: "Open ${dateMatch.group(
                    1)}/${startMonth} - ${dateMatch.group(3)}/${endMonth}");
          }
        }
      }
    } catch (e) {
      /* Fall through */
    }

    // === RULE 19: Seasonal "Από [Month] έως [Month]... (HH:MM - HH:MM)" (Handles 5531, 710) ===
    try {
      final match = RegExp(
          r'από\s*(\w+)\s*έως\s*(\w+),\s*καθημερινά:\s*\((\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})\)')
          .firstMatch(text);
      if (match != null) {
        final startMonth = _monthMap[match.group(1)!];
        final endMonth = _monthMap[match.group(2)!];
        if (startMonth != null && endMonth != null) {
          final oh = int.parse(match.group(3)!);
          final om = int.parse(match.group(4)!);
          final ch = int.parse(match.group(5)!);
          final cm = int.parse(match.group(6)!);

          final bool isInSeason;
          if (startMonth <= endMonth) {
            isInSeason = currentMonth >= startMonth && currentMonth <= endMonth;
          } else { // Wraps around year end (e.g., Oct - May)
            isInSeason = currentMonth >= startMonth || currentMonth <= endMonth;
          }

          if (isInSeason) {
            return _checkTime(now, oh, om, ch, cm, "Seasonal");
          } else {
            return AvailabilityStatus(isOpen: false,
                isUncertain: false,
                displayText: 'Closed (Seasonal)');
          }
        }
      }
    } catch (e) {
      /* Fall through */
    }

    // === RULE 20: Simple Time Range (HH:MM-HH:MM) (Handles 431, 11272, 12004, 12316, 11904, 11913, 11272) ===
    try {
      // Matches start-of-string, HH:MM, separator, HH:MM, end-of-string
      final match = RegExp(
          r'^(\d{1,2})[:.](\d{2})\s*[-–με]\s*(\d{1,2})[:.](\d{2})$').firstMatch(
          text);
      if (match != null) {
        final oh = int.parse(match.group(1)!);
        final om = int.parse(match.group(2)!);
        final ch = int.parse(match.group(3)!);
        final cm = int.parse(match.group(4)!);
        return _checkTime(now, oh, om, ch, cm, "Daily");
      }
    } catch (e) {
      /* Fall..." */
    }

    // === RULE 21: Weekday/Weekend Split (Handles 2256, 12010) ===
    try {
      final weekdayMatch = RegExp(
          r'(?:δευτέρα έως παρασκευή|καθημεριν[αά] απο τις)\s*\(?(\d{1,2})[:.](\d{2})\s*(?:πμ|μμ)?\s*[-–έως]\s*(\d{1,2})[:.](\d{2})\s*(?:πμ|μμ)?\)?')
          .firstMatch(text);
      final weekendMatch = RegExp(
          r'(?:σαββατοκύριακο|σάββατο)\s*\(?(\d{1,2})[:.](\d{2})\s*(?:πμ|μμ)?\s*[-–έως]\s*(\d{1,2})[:.](\d{2})\s*(?:πμ|μμ)?\)?')
          .firstMatch(text);

      if (weekdayMatch != null && weekendMatch != null) {
        final isWeekday = currentDay >= 1 && currentDay <= 5;
        final match = isWeekday ? weekdayMatch : weekendMatch;

        // Fix from previous step: removed redundant null check
        final oh = int.parse(match.group(1)!);
        final om = int.parse(match.group(2)!);
        final ch = int.parse(match.group(3)!);
        final cm = int.parse(match.group(4)!);
        return _checkTime(
            now, oh, om, ch, cm, isWeekday ? "Weekdays" : "Weekend");
      }
    } catch (e) {
      /* Fall through */
    }

    // === RULE 22: Weekday with Split Time (Handles 140) ===
    try {
      final match = RegExp(
          r'δευτέρα έως παρασκευή\s*\(?(\d{1,2})[:.](\d{2})\s*[-–]\s*(\d{1,2})[:.](\d{2})\s*&\s*(\d{1,2})[:.](\d{2})\s*[-–]\s*(\d{1,2})[:.](\d{2})\)?')
          .firstMatch(text);
      if (match != null) {
        final isWeekday = currentDay >= 1 && currentDay <= 5;
        if (isWeekday) {
          final oh1 = int.parse(match.group(1)!);
          final om1 = int.parse(match.group(2)!);
          final ch1 = int.parse(match.group(3)!);
          final cm1 = int.parse(match.group(4)!);
          final r1 = _checkTime(now, oh1, om1, ch1, cm1, "Weekdays");
          if (r1.isOpen) return r1;

          final oh2 = int.parse(match.group(5)!);
          final om2 = int.parse(match.group(6)!);
          final ch2 = int.parse(match.group(7)!);
          final cm2 = int.parse(match.group(8)!);
          final r2 = _checkTime(now, oh2, om2, ch2, cm2, "Weekdays");
          if (r2.isOpen) return r2;

          return AvailabilityStatus(isOpen: false,
              isUncertain: false,
              displayText: "Closed",
              detailText: "Opens ${oh1.toString().padLeft(2, '0')}:${om1
                  .toString().padLeft(2, '0')}");
        } else {
          return AvailabilityStatus(isOpen: false,
              isUncertain: false,
              displayText: "Closed (Weekends)");
        }
      }
    } catch (e) {
      /* Fall through */
    }

    // === RULE 23: Daily "Καθημερινά" (Handles 73, 9811, 3196, 353, 2231, 3724, 895, 268, etc.) ===
    try {
      // More robust: catches "Καθημερινά:", (HH:MM - HH:MM) or HH:MM - HH:MM, with πμ/μμ
      final dailyMatch = RegExp(
          r'(?:καθημερινά:|καθημερινά|κάθε μέρα|προσβασιμος ολη την εβδομαδα απο τις|από)\s*\(?(\d{1,2})[:.]?(\d{2})\s*(?:πμ|μμ)?\s*[-–έως]\s*(\d{1,2})[:.]?(\d{2})\s*(?:πμ|μμ)?\)?')
          .firstMatch(text);
      if (dailyMatch != null) {
        final oh = int.parse(dailyMatch.group(1)!);
        final om = int.parse(dailyMatch.group(2)!);
        final ch = int.parse(dailyMatch.group(3)!);
        final cm = int.parse(dailyMatch.group(4)!);
        return _checkTime(now, oh, om, ch, cm, "Daily");
      }
    } catch (e) {
      /* Fall through */
    }

    // === RULE 24: Simple Weekday "ΔΕΥΤΕΡΑ-ΠΑΡΑΣΚΕΥΗ HH:MM-HH:MM" (Handles 11565, 4470, 12816, 12815, 12818) ===
    try {
      // More robust: no parens, optional minutes
      final weekdayMatch = RegExp(
          r'(?:δευτέρα\s*[-–με]\s*παρασκευή|καθημερινές|εργάσιμες ημέρες)\s*.*?(\d{1,2})(?:[:.](\d{2}))?\s*(?:πμ|μμ)?\s*[-–έως]\s*(\d{1,2})(?:[:.](\d{2}))?\s*(?:πμ|μμ)?')
          .firstMatch(text);
      if (weekdayMatch != null) {
        final isWeekday = currentDay >= 1 && currentDay <= 5;
        if (isWeekday) {
          final oh = int.parse(weekdayMatch.group(1)!);
          final om = int.tryParse(weekdayMatch.group(2) ?? '0') ?? 0;
          final ch = int.parse(weekdayMatch.group(3)!);
          final cm = int.tryParse(weekdayMatch.group(4) ?? '0') ?? 0;
          // Handle '9-5' (9:00 - 17:00)
          final ch_adjusted = (ch < oh || ch <= 12) ? ch + 12 : ch;
          return _checkTime(now, oh, om, ch_adjusted, cm, "Weekdays");
        } else {
          return AvailabilityStatus(isOpen: false,
              isUncertain: false,
              displayText: 'Closed (Weekends)');
        }
      }
    } catch (e) {
      /* Fall..." */
    }

    // === RULE 25: Weekday/Sat Split (Handles 11402, 11401, 12319) ===
    try {
      final weekdayMatch = RegExp(
          r'(?:δευτέρα\s*[-–έως]\s*παρασκευή|απο δευτερα μεχρι παρασκευη)\s*.*?(\d{1,2})(?:[:.](\d{2}))?\s*(?:πμ|μμ)?\s*[-–με]\s*(\d{1,2})(?:[:.](\d{2}))?\s*(?:πμ|μμ)?')
          .firstMatch(text);
      final satMatch = RegExp(
          r'(?:σάββατο|και το σαββατο)\s*.*?(\d{1,2})(?:[:.](\d{2}))?\s*(?:πμ|μμ)?\s*[-–με]\s*(\d{1,2})(?:[:.](\d{2}))?\s*(?:πμ|μμ)?')
          .firstMatch(text);

      if (weekdayMatch != null && satMatch != null) {
        final isWeekday = currentDay >= 1 && currentDay <= 5;
        final isSaturday = currentDay == 6;

        if (isWeekday) {
          final oh = int.parse(weekdayMatch.group(1)!);
          final om = int.tryParse(weekdayMatch.group(2) ?? '0') ?? 0;
          final ch = int.parse(weekdayMatch.group(3)!);
          final cm = int.tryParse(weekdayMatch.group(4) ?? '0') ?? 0;
          // Handle '9πμ -9αμ' -> 9:00 - 21:00
          final ch_adjusted = (ch == oh && text.contains('πμ') &&
              text.contains('αμ')) ? ch + 12 : (ch < oh ? ch + 12 : ch);
          return _checkTime(now, oh, om, ch_adjusted, cm, "Weekdays");
        } else if (isSaturday) {
          final oh = int.parse(satMatch.group(1)!);
          final om = int.tryParse(satMatch.group(2) ?? '0') ?? 0;
          final ch = int.parse(satMatch.group(3)!);
          final cm = int.tryParse(satMatch.group(4) ?? '0') ?? 0;
          final ch_adjusted = (ch < oh || ch <= 12)
              ? ch + 12
              : ch; // Handle '9-5' -> 9:00 - 17:00
          return _checkTime(now, oh, om, ch_adjusted, cm, "Saturday");
        } else {
          return AvailabilityStatus(isOpen: false,
              isUncertain: false,
              displayText: 'Closed (Sunday)');
        }
      }
    } catch (e) {
      /* Fall through */
    }

    // === RULE 26: "Μόνο το καλοκαίρι" = Summer only (May-September) ===
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

    // === RULE 27: Parse specific day/time patterns like "Δευτέρα έως Παρασκευή 7:00 - 16:00" ===
    final specificHours = _parseSpecificHours(availability, now);
    if (specificHours != null) {
      return specificHours;
    }

    // === FINAL RULE: Unknown format ===
    log(
      "Unhandled availability string: '$availability'",
      name: "AvailabilityParser",
      error: "AED ID: ${aedId ?? 'Unknown'}",
    );
    return AvailabilityStatus(
      isOpen: true,
      isUncertain: true,
      displayText: availability,
    );
  } // 👈 *** THIS IS THE END of parseAvailability ***

  /// Helper to get current minutes in day
  static int currentMinutes(DateTime now) {
    return now.hour * 60 + now.minute;
  }

  /// ✅ NEW HELPER: Checks time and returns status
  static AvailabilityStatus _checkTime(DateTime now, int openHour, int openMin,
      int closeHour, int closeMin, String detailText) {
    final currentMinutes = now.hour * 60 + now.minute;
    final openMinutes = openHour * 60 + openMin;

    // Handle closing time past midnight (e.g., 08:00 - 01:00)
    int closeMinutes = (closeHour * 60) + closeMin;
    if (closeMinutes <= openMinutes) { // Use <= to handle 9am-9am
      closeMinutes += 24 * 60; // Add 24 hours
    }

    // Adjust current minutes if we are checking for a time past midnight
    int checkMinutes = currentMinutes;
    if (now.hour < openHour && closeMinutes > (24 * 60)) {
      checkMinutes += 24 * 60;
    }

    final openTime = "${openHour.toString().padLeft(2, '0')}:${openMin
        .toString().padLeft(2, '0')}";
    final closeTime = "${closeHour.toString().padLeft(2, '0')}:${closeMin
        .toString().padLeft(2, '0')}";
    final detail = "$detailText ($openTime - $closeTime)";

    if (checkMinutes >= openMinutes && checkMinutes < closeMinutes) {
      return AvailabilityStatus(
        isOpen: true,
        isUncertain: false,
        displayText: 'Open now',
        detailText: 'Closes at $closeTime',
      );
    } else {
      return AvailabilityStatus(
        isOpen: false,
        isUncertain: false,
        displayText: 'Closed',
        detailText: 'Opens at $openTime ($detail)',
      );
    }
  }

  /// ✅ Parse specific hours like "Δευτέρα έως Παρασκευή 7:00 - 16:00"
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
    final timePattern = RegExp(
        r'(\d{1,2})[:.](\d{2})\s*-\s*(\d{1,2})[:.](\d{2})');
    final timeMatch = timePattern.firstMatch(text);

    if (timeMatch != null) {
      openHour = int.tryParse(timeMatch.group(1)!);
      openMinute = int.tryParse(timeMatch.group(2)!);
      closeHour = int.tryParse(timeMatch.group(3)!);
      closeMinute = int.tryParse(timeMatch.group(4)!);
    }

    // If we successfully parsed everything, check current time
    if (startDay != null && endDay != null && openHour != null &&
        closeHour != null) {
      final currentDay = now.weekday;

      // Check if current day is in range
      final bool isInDayRange;
      if (startDay <= endDay) {
        isInDayRange = currentDay >= startDay && currentDay <= endDay;
      } else {
        // Handle ranges that cross the end of the week (e.g., Sat - Tue)
        isInDayRange = currentDay >= startDay || currentDay <= endDay;
      }

      if (isInDayRange) {
        return _checkTime(
            now, openHour, openMinute ?? 0, closeHour, closeMinute ?? 0,
            "${_getDayName(startDay)} - ${_getDayName(endDay)}");
      } else {
        return AvailabilityStatus(
          isOpen: false,
          isUncertain: false,
          displayText: 'Closed',
          detailText: 'Open ${_getDayName(startDay)} - ${_getDayName(endDay)}',
        );
      }
    }

    return null; // Couldn't parse
  }

  static String _getDayName(int day) {
    switch (day) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return 'Weekdays';
    }
  }
}

extension on AvailabilityStatus {
  AvailabilityStatus copyWith({
    bool? isOpen,
    bool? isUncertain,
    String? displayText,
    String? detailText,
  }) {
    return AvailabilityStatus(
      isOpen: isOpen ?? this.isOpen,
      isUncertain: isUncertain ?? this.isUncertain,
      displayText: displayText ?? this.displayText,
      detailText: detailText ?? this.detailText,
    );
  }
}