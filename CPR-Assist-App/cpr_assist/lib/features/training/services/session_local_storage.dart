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
// Max 50 sessions — synced sessions evicted first, then oldest unsynced.
// ─────────────────────────────────────────────────────────────────────────────

class SessionLocalStorage {
  static const String _indexKey    = 'session_local_keys';
  static const int    _maxSessions = 50;

  /// Stable storage key for a session: sessionStart truncated to whole seconds,
  /// expressed as ms since epoch. Matches the backend's session_start truncation
  /// (session.js strips sub-second precision before INSERT/UPSERT), so the same
  /// session has identical keys on both sides regardless of timezone.
  static int keyMsFromStart(DateTime start) =>
      start.copyWith(millisecond: 0, microsecond: 0).millisecondsSinceEpoch;

  static int _keyMs(SessionDetail d) => keyMsFromStart(d.sessionStart);

  // ── Save ───────────────────────────────────────────────────────────────────

  static Future<bool> saveLocal(SessionDetail detail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = 'session_local_${_keyMs(detail)}';

      // Write the session
      await prefs.setString(key, jsonEncode(detail.toJson()));

      // Update index
      final keys = _readIndex(prefs)..remove(key)..add(key);

      // Evict synced sessions first, then oldest unsynced as last resort.
      // Eviction is silent — synced sessions are already on the backend.
      while (keys.length > _maxSessions) {
        String? toEvict;
        for (final k in keys) {
          final raw = prefs.getString(k);
          if (raw == null) { toEvict = k; break; }
          try {
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            if (decoded['syncedToBackend'] == true) { toEvict = k; break; }
          } catch (_) {
            toEvict = k;
            break;
          }
        }
        toEvict ??= keys.first;
        keys.remove(toEvict);
        await prefs.remove(toEvict);
        debugPrint('SessionLocalStorage: evicted $toEvict (limit $_maxSessions)');
      }

      await prefs.setString(_indexKey, jsonEncode(keys));
      debugPrint('SessionLocalStorage: saved $key');
      return true;
    } catch (e) {
      debugPrint('SessionLocalStorage: save failed — $e');
      return false;
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
      final prefs = await SharedPreferences.getInstance();
      final key   = 'session_local_${_keyMs(detail)}';
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
      final key   = 'session_local_${_keyMs(detail)}';
      await prefs.remove(key);
      final keys  = _readIndex(prefs)..remove(key);
      await prefs.setString(_indexKey, jsonEncode(keys));
    } catch (e) {
      debugPrint('SessionLocalStorage: delete failed — $e');
    }
  }

  /// Delete a local session by its sessionStart (no detail object required).
  /// Used by the backend-delete flow to clean the local cache in one call.
  /// No-op if no local record matches.
  static Future<void> deleteByStart(DateTime sessionStart) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = 'session_local_${keyMsFromStart(sessionStart)}';
      await prefs.remove(key);
      final keys  = _readIndex(prefs)..remove(key);
      await prefs.setString(_indexKey, jsonEncode(keys));
    } catch (e) {
      debugPrint('SessionLocalStorage: deleteByStart failed — $e');
    }
  }

  /// Wipe every locally stored session. Pairs with backend DELETE /sessions/all.
  static Future<void> deleteAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys  = _readIndex(prefs);
      for (final key in keys) {
        await prefs.remove(key);
      }
      await prefs.remove(_indexKey);
    } catch (e) {
      debugPrint('SessionLocalStorage: deleteAll failed — $e');
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