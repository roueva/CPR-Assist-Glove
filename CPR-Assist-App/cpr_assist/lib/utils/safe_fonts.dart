import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SafeFonts {
  static bool _useGoogleFonts = true;
  static final Map<String, TextStyle> _cachedStyles = {};

  /// Initialize with cached Google Fonts (call this during app startup)
  static void initializeFontCache() {
    try {
      // Pre-cache common font styles to avoid loading delays
      _cacheFont('Inter', 12, FontWeight.normal);
      _cacheFont('Inter', 14, FontWeight.normal);
      _cacheFont('Inter', 16, FontWeight.normal);
      _cacheFont('Inter', 18, FontWeight.bold);
      _cacheFont('Poppins', 10, FontWeight.w600);
      _cacheFont('Poppins', 12, FontWeight.normal);

      print("📱 Font cache initialized");
    } catch (e) {
      print("⚠️ Font cache initialization failed: $e");
      _useGoogleFonts = false;
    }
  }

  static void _cacheFont(String fontFamily, double fontSize, FontWeight weight) {
    final key = '${fontFamily}_${fontSize}_${weight.index}';
    try {
      if (fontFamily == 'Inter') {
        _cachedStyles[key] = GoogleFonts.inter(fontSize: fontSize, fontWeight: weight);
      } else if (fontFamily == 'Poppins') {
        _cachedStyles[key] = GoogleFonts.poppins(fontSize: fontSize, fontWeight: weight);
      }
    } catch (e) {
      // Fallback to system font if Google Fonts fails
      _cachedStyles[key] = TextStyle(
        fontFamily: fontFamily == 'Inter' ? 'System' : 'System',
        fontSize: fontSize,
        fontWeight: weight,
      );
    }
  }

  static void enableGoogleFonts() {
    _useGoogleFonts = true;
  }

  static void disableGoogleFonts() {
    // Don't actually disable - just note the offline state
    // We'll still use cached fonts for consistency
    print("📱 App is offline - using cached fonts for consistency");
  }

  static TextStyle inter({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double? height,
    TextDecoration? decoration,
  }) {
    final key = 'Inter_${fontSize}_${fontWeight.index}';

    TextStyle baseStyle;
    if (_cachedStyles.containsKey(key)) {
      baseStyle = _cachedStyles[key]!;
    } else {
      // Create and cache on demand
      try {
        if (_useGoogleFonts) {
          baseStyle = GoogleFonts.inter(fontSize: fontSize, fontWeight: fontWeight);
          _cachedStyles[key] = baseStyle;
        } else {
          baseStyle = TextStyle(
            fontFamily: 'System',
            fontSize: fontSize,
            fontWeight: fontWeight,
          );
        }
      } catch (e) {
        baseStyle = TextStyle(
          fontFamily: 'System',
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      }
    }

    // Apply additional properties
    return baseStyle.copyWith(
      color: color,
      height: height,
      decoration: decoration,
    );
  }

  static TextStyle poppins({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color? color,
    double? height,
    TextDecoration? decoration,
  }) {
    final key = 'Poppins_${fontSize}_${fontWeight.index}';

    TextStyle baseStyle;
    if (_cachedStyles.containsKey(key)) {
      baseStyle = _cachedStyles[key]!;
    } else {
      // Create and cache on demand
      try {
        if (_useGoogleFonts) {
          baseStyle = GoogleFonts.poppins(fontSize: fontSize, fontWeight: fontWeight);
          _cachedStyles[key] = baseStyle;
        } else {
          baseStyle = TextStyle(
            fontFamily: 'System',
            fontSize: fontSize,
            fontWeight: fontWeight,
          );
        }
      } catch (e) {
        baseStyle = TextStyle(
          fontFamily: 'System',
          fontSize: fontSize,
          fontWeight: fontWeight,
        );
      }
    }

    // Apply additional properties
    return baseStyle.copyWith(
      color: color,
      height: height,
      decoration: decoration,
    );
  }

  /// Get cache statistics for debugging
  static Map<String, dynamic> getCacheStats() {
    return {
      'cachedStyles': _cachedStyles.length,
      'useGoogleFonts': _useGoogleFonts,
    };
  }

  /// Clear font cache (useful for memory management)
  static void clearCache() {
    _cachedStyles.clear();
    print("📱 Font cache cleared");
  }
}