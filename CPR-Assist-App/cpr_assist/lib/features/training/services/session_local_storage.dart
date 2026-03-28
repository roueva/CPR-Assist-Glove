import 'dart:convert';
import 'package:cpr_assist/features/training/services/session_detail.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SessionLocalStorage
//
// Saves SessionDetail records to SharedPreferences so sessions survive
// offline conditions (no internet or user not logged in).
//
// Key scheme:
//   session_local_keys  — JSON list of all active local session keys
//   session_local_<ms>  — JSON-encoded SessionDetail for that session
//
// Max 20 sessions — oldest evicted when limit is reached.
// ─────────────────────────────────────────────────────────────────────────────

class SessionLocalStorage {
  static const String _indexKey    = 'session_local_keys';
  static const int    _maxSessions = 20;
  /// Called when sessions are evicted due to the local storage limit.
  /// Set this from your app entry point or wherever UIHelper is accessible.
  static void Function(int evictedCount)? onEviction;

  // ── Save ───────────────────────────────────────────────────────────────────

  static Future<void> saveLocal(SessionDetail detail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = 'session_local_${detail.sessionStart.millisecondsSinceEpoch}';

      // Write the session
      await prefs.setString(key, jsonEncode(detail.toJson()));

      // Update index
      final keys = _readIndex(prefs)..remove(key)..add(key);

      // Evict oldest if over limit
      int evicted = 0;
      while (keys.length > _maxSessions) {
        final oldest = keys.removeAt(0);
        await prefs.remove(oldest);
        evicted++;
      }
      if (evicted > 0) {
        debugPrint(
          'SessionLocalStorage: evicted $evicted old session(s) — '
              'device storage limit ($_maxSessions) reached',
        );
        onEviction?.call(evicted);
      }

      await prefs.setString(_indexKey, jsonEncode(keys));
      debugPrint('SessionLocalStorage: saved $key');
    } catch (e) {
      debugPrint('SessionLocalStorage: save failed — $e');
    }
  }

  // ── Load all ───────────────────────────────────────────────────────────────

  /// Returns all locally stored SessionDetail records, sorted newest first.
  static Future<List<SessionDetail>> loadAll() async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final keys   = _readIndex(prefs);
      final result = <SessionDetail>[];

      for (final key in keys) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final json   = jsonDecode(raw) as Map<String, dynamic>;
          final detail = SessionDetail.fromJson(json);
          result.add(detail);
        } catch (e) {
          debugPrint('SessionLocalStorage: failed to parse $key — $e');
        }
      }

      // Newest first
      result.sort((a, b) => b.sessionStart.compareTo(a.sessionStart));
      return result;
    } catch (e) {
      debugPrint('SessionLocalStorage: loadAll failed — $e');
      return [];
    }
  }

  // ── Mark synced ────────────────────────────────────────────────────────────

  /// Marks a session as synced to backend. Keeps it locally for display.
  static Future<void> markSynced(SessionDetail detail) async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final key    = 'session_local_${detail.sessionStart.millisecondsSinceEpoch}';
      final synced = detail.markSynced();
      await prefs.setString(key, jsonEncode(synced.toJson()));
    } catch (e) {
      debugPrint('SessionLocalStorage: markSynced failed — $e');
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  static Future<void> deleteLocal(SessionDetail detail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = 'session_local_${detail.sessionStart.millisecondsSinceEpoch}';
      await prefs.remove(key);
      final keys  = _readIndex(prefs)..remove(key);
      await prefs.setString(_indexKey, jsonEncode(keys));
    } catch (e) {
      debugPrint('SessionLocalStorage: delete failed — $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static List<String> _readIndex(SharedPreferences prefs) {
    final raw = prefs.getString(_indexKey);
    if (raw == null) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }
}