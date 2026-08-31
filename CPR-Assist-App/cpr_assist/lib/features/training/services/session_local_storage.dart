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
//   session_local_keys_<ownerId>       — JSON list of that owner's session keys
//   session_local_<ownerId>_<ms>       — JSON-encoded SessionDetail for that session
//
// Max 50 sessions — synced sessions evicted first, then oldest unsynced.
// ─────────────────────────────────────────────────────────────────────────────

class SessionLocalStorage {
  static const String _defaultOwner = 'anon';
  static const int    _maxSessions  = 50;

  /// ownerId is the logged-in user's id as a string, or 'anon' when no one
  /// is logged in. This is what stops one account from seeing another
  /// account's cached sessions.
  static String _indexKey(String ownerId) => 'session_local_keys_$ownerId';
  static String _recordKey(String ownerId, int ms) => 'session_local_${ownerId}_$ms';

  static int keyMsFromStart(DateTime start) =>
      start.copyWith(millisecond: 0, microsecond: 0).millisecondsSinceEpoch;

  static int _keyMs(SessionDetail d) => keyMsFromStart(d.sessionStart);

  // ── Save ───────────────────────────────────────────────────────────────────

  static Future<bool> saveLocal(SessionDetail detail, {required String ownerId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = _recordKey(ownerId, _keyMs(detail));

      // Write the session
      await prefs.setString(key, jsonEncode(detail.toJson()));

      // Update index
      final keys = _readIndex(prefs, ownerId)..remove(key)..add(key);

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

      await prefs.setString(_indexKey(ownerId), jsonEncode(keys));
      debugPrint('SessionLocalStorage: saved $key');
      return true;
    } catch (e) {
      debugPrint('SessionLocalStorage: save failed — $e');
      return false;
    }
  }

  // ── Load all ───────────────────────────────────────────────────────────────

  /// Returns all locally stored SessionDetail records, sorted newest first.
  static Future<List<SessionDetail>> loadAll({required String ownerId}) async {
    try {
      final prefs  = await SharedPreferences.getInstance();
      final keys   = _readIndex(prefs, ownerId);
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
  static Future<void> markSynced(SessionDetail detail, {required String ownerId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = _recordKey(ownerId, _keyMs(detail));
      if (!prefs.containsKey(key)) return;
      final synced = detail.markSynced();
      await prefs.setString(key, jsonEncode(synced.toJson()));
    } catch (e) {
      debugPrint('SessionLocalStorage: markSynced failed — $e');
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// Delete a local session by its sessionStart (no detail object required).
  /// Used by the backend-delete flow to clean the local cache in one call.
  /// No-op if no local record matches.
  static Future<void> deleteByStart(DateTime sessionStart, {required String ownerId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key   = _recordKey(ownerId, keyMsFromStart(sessionStart));
      await prefs.remove(key);
      final keys  = _readIndex(prefs, ownerId)..remove(key);
      await prefs.setString(_indexKey(ownerId), jsonEncode(keys));
    } catch (e) {
      debugPrint('SessionLocalStorage: deleteByStart failed — $e');
    }
  }
  /// One-time maintenance: remove every locally-stored session that has NOT
  /// synced to the backend, across all owners (anon + any user id). Synced
  /// records are kept — they also live on the server. Returns count removed.
  static Future<int> purgeAllUnsynced() async {
    final prefs = await SharedPreferences.getInstance();
    int removed = 0;

    final recordKeys = prefs.getKeys().where((k) =>
    k.startsWith('session_local_') &&
        !k.startsWith('session_local_keys_')).toList();

    for (final k in recordKeys) {
      final raw = prefs.getString(k);
      bool synced = false;
      if (raw != null) {
        try {
          synced = (jsonDecode(raw)
          as Map<String, dynamic>)['syncedToBackend'] == true;
        } catch (_) {
          synced = false; // malformed → treat as junk, remove
        }
      }
      if (!synced) {
        await prefs.remove(k);
        removed++;
      }
    }

    // Rebuild every owner index to drop keys that no longer exist.
    final indexKeys = prefs.getKeys()
        .where((k) => k.startsWith('session_local_keys_')).toList();
    for (final idxKey in indexKeys) {
      final owner = idxKey.substring('session_local_keys_'.length);
      final surviving =
      _readIndex(prefs, owner).where(prefs.containsKey).toList();
      await prefs.setString(idxKey, jsonEncode(surviving));
    }

    debugPrint('SessionLocalStorage: purged $removed unsynced records');
    return removed;
  }

  /// Wipe every locally stored session. Pairs with backend DELETE /sessions/all.
  static Future<void> deleteAll({required String ownerId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys  = _readIndex(prefs, ownerId);
      for (final key in keys) {
        await prefs.remove(key);
      }
      await prefs.remove(_indexKey(ownerId));
    } catch (e) {
      debugPrint('SessionLocalStorage: deleteAll failed — $e');
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static List<String> _readIndex(SharedPreferences prefs, String ownerId) {
    final raw = prefs.getString(_indexKey(ownerId));
    if (raw == null) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  /// Moves every session owned by [from] into [to]. Called on login so a
  /// session saved anonymously (Emergency mode, before the post-session
  /// login prompt) gets attached to the account instead of staying orphaned.
  static Future<void> migrateOwner({required String from, required String to}) async {
    if (from == to) return;
    try {
      final prefs    = await SharedPreferences.getInstance();
      final fromKeys = _readIndex(prefs, from);
      if (fromKeys.isEmpty) return;

      final toKeys = _readIndex(prefs, to);
      for (final oldKey in fromKeys) {
        final raw = prefs.getString(oldKey);
        if (raw == null) continue;
        final ms = int.tryParse(oldKey.split('_').last);
        if (ms == null) continue;
        final newKey = _recordKey(to, ms);
        await prefs.setString(newKey, raw);
        toKeys..remove(newKey)..add(newKey);
      }
      // Index written before old records are removed, so a crash mid-loop
      // leaves migrated records reachable and retry is idempotent.
      await prefs.setString(_indexKey(to), jsonEncode(toKeys));
      for (final oldKey in fromKeys) {
        await prefs.remove(oldKey);
      }
      await prefs.remove(_indexKey(from));
      debugPrint('SessionLocalStorage: migrated ${fromKeys.length} session(s) from $from to $to');
    } catch (e) {
      debugPrint('SessionLocalStorage: migrateOwner failed — $e');
    }
  }

  /// ONE-TIME cleanup of data written before per-owner scoping existed.
  /// Old keys ('session_local_keys' / 'session_local_<ms>', no owner suffix)
  /// are read once: already-synced sessions (have a backend id) are just
  /// dropped locally — they're safe on the backend for whichever account
  /// really owns them. Unsynced sessions (id == null, truly local-only) are
  /// migrated into the 'anon' bucket so they aren't lost. Safe to call
  /// every app start — it's a no-op once the legacy keys are gone.
  static Future<void> migrateLegacyUnscopedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString('session_local_keys');
      if (raw == null) return;
      final legacyKeys = List<String>.from(jsonDecode(raw) as List);

      final anonKeys = _readIndex(prefs, _defaultOwner);
      for (final oldKey in legacyKeys) {
        final json = prefs.getString(oldKey);
        if (json != null) {
          try {
            final decoded = jsonDecode(json) as Map<String, dynamic>;
            final ms = int.tryParse(oldKey.split('_').last);
            if (decoded['id'] == null && ms != null) {
              final newKey = _recordKey(_defaultOwner, ms);
              await prefs.setString(newKey, json);
              anonKeys..remove(newKey)..add(newKey);
            }
          } catch (_) {}
        }
      }
      // Index written before old records are removed, so a crash mid-loop
      // leaves migrated records reachable and retry is idempotent.
      await prefs.setString(_indexKey(_defaultOwner), jsonEncode(anonKeys));
      for (final oldKey in legacyKeys) {
        await prefs.remove(oldKey);
      }
      await prefs.remove('session_local_keys');
      debugPrint('SessionLocalStorage: legacy migration done (${legacyKeys.length} old key(s))');
    } catch (e) {
      debugPrint('SessionLocalStorage: migrateLegacyUnscopedData failed — $e');
    }
  }
}