const express = require('express');
const { body, validationResult } = require('express-validator');

module.exports = function (pool) {
    const router = express.Router();
    const { authenticate } = require('../middleware/validation');

    // Endpoint to save a session summary
    router.post(
        '/summary',
        authenticate,
        [
            body('compression_count').isInt().withMessage('Compression count must be an integer'),
            body('correct_depth').isInt().withMessage('Correct depth must be an integer'),
            body('correct_frequency').isInt().withMessage('Correct frequency must be an integer'),
            body('correct_rebound').optional().isBoolean().withMessage('Correct rebound must be a boolean'),
            body('patient_heart_rate').optional().isInt().withMessage('Patient heart rate must be an integer'),
            body('patient_temperature').optional().isFloat().withMessage('Patient temperature must be a float'),
            body('user_heart_rate').optional().isInt().withMessage('User heart rate must be an integer'),
            body('user_temperature').optional().isFloat().withMessage('User temperature must be a float'),
            body('session_duration').isInt().withMessage('Session duration must be an integer'),
            body('correct_recoil').optional().isInt({ min: 0 }).withMessage('Correct recoil must be a non-negative integer'),
            body('depth_rate_combo').optional().isInt({ min: 0 }).withMessage('Depth rate combo must be a non-negative integer'),
            body('average_depth').optional().isFloat({ min: 0 }).withMessage('Average depth must be a non-negative number'),
            body('average_frequency').optional().isFloat({ min: 0 }).withMessage('Average frequency must be a non-negative number'),
            body('total_grade').optional().isFloat({ min: 0, max: 100 }).withMessage('Total grade must be between 0 and 100'),
            body('session_start').optional().isISO8601().withMessage('Session start must be a valid ISO date'),
        ],
        async (req, res, next) => {
            const errors = validationResult(req);
            if (!errors.isEmpty()) {
                return res.status(400).json({ errors: errors.array() });
            }

            const user_id = req.user.id;
            const {
                compression_count,
                correct_depth,
                correct_frequency,
                correct_rebound,
                patient_heart_rate,
                patient_temperature,
                user_heart_rate,
                user_temperature,
                session_duration,
                correct_recoil,
                depth_rate_combo,
                average_depth,
                average_frequency,
                total_grade,
                session_start,
            } = req.body;

            try {
                await pool.query(
                    `INSERT INTO cpr_sessions 
    (user_id, compression_count, correct_depth, correct_frequency,
     correct_recoil, depth_rate_combo, average_depth, average_frequency,
     correct_rebound, patient_heart_rate, patient_temperature,
     user_heart_rate, user_temperature, session_duration,
     total_grade, session_start, session_end)
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,NOW())`,
                    [
                        user_id,
                        compression_count,
                        correct_depth,
                        correct_frequency,
                        correct_recoil ?? 0,
                        depth_rate_combo ?? 0,
                        average_depth ?? 0.0,
                        average_frequency ?? 0.0,
                        correct_rebound ?? false,
                        patient_heart_rate ?? null,
                        patient_temperature ?? null,
                        user_heart_rate ?? null,
                        user_temperature ?? null,
                        session_duration,
                        total_grade ?? 0.0,
                        session_start ?? new Date().toISOString(),
                    ]
                );

                res.json({ success: true, message: 'Session summary saved successfully.' });
            } catch (err) {
                console.error('Error saving session summary:', err.message);
                next(err);
            }
        }
    );

    // Endpoint to fetch session summaries for the logged-in user
    router.get('/summaries', authenticate, async (req, res) => {
        try {
            const user_id = req.user.id;

            const result = await pool.query(
                `SELECT id, compression_count, correct_depth, correct_frequency,
        correct_recoil, depth_rate_combo, average_depth, average_frequency,
        correct_rebound, patient_heart_rate, patient_temperature,
        user_heart_rate, user_temperature, session_duration,
        total_grade, session_start, session_end
 FROM cpr_sessions
 WHERE user_id = $1
 ORDER BY session_start DESC`,
                [user_id]
            );

            res.json({
                success: true,
                data: result.rows,
            });
        } catch (err) {
            console.error('Error fetching session summaries:', err.message);
            res.status(500).json({
                success: false,
                message: 'Failed to fetch session summaries.',
                error: err.message,
            });
        }
    });

    // The leaderboard Personal Best card calls this instead of scanning all sessions
    // client-side. Faster on large session counts.

    router.get('/best', authenticate, async (req, res) => {
        const userId = req.user.id;
        try {
            const result = await pool.query(
                `SELECT id, compression_count, correct_depth, correct_frequency,
              correct_recoil, depth_rate_combo, average_depth, average_frequency,
              correct_rebound, patient_heart_rate, patient_temperature,
              user_heart_rate, user_temperature, session_duration,
              total_grade, session_start, session_end
       FROM cpr_sessions
       WHERE user_id = $1
       ORDER BY total_grade DESC
       LIMIT 1`,
                [userId]
            );

            if (result.rows.length === 0) {
                return res.json({ success: true, data: null });
            }

            res.json({ success: true, data: result.rows[0] });
        } catch (err) {
            console.error('Error fetching best session:', err.message);
            res.status(500).json({ success: false, message: 'Failed to fetch best session.' });
        }
    });

    // ── DELETE /sessions/all — delete ALL sessions for current user ─────────────
    // Called from Settings → Delete all session data.

    router.delete('/all', authenticate, async (req, res) => {
        const userId = req.user.id;
        try {
            const result = await pool.query(
                'DELETE FROM cpr_sessions WHERE user_id = $1 RETURNING id',
                [userId]
            );
            res.json({
                success: true,
                message: `Deleted ${result.rowCount} session(s).`,
                deleted_count: result.rowCount,
            });
        } catch (err) {
            console.error('Error deleting all sessions:', err.message);
            res.status(500).json({ success: false, message: 'Failed to delete sessions.' });
        }
    });

    // ── DELETE /sessions/:id — delete a single session ──────────────────────────
    // For the "Delete all session data" settings option and future per-session delete.

    router.delete('/:id', authenticate, async (req, res) => {
        const userId = req.user.id;
        const sessionId = parseInt(req.params.id);

        if (isNaN(sessionId)) {
            return res.status(400).json({ success: false, message: 'Invalid session ID.' });
        }

        try {
            // Verify ownership before deleting
            const result = await pool.query(
                'DELETE FROM cpr_sessions WHERE id = $1 AND user_id = $2 RETURNING id',
                [sessionId, userId]
            );

            if (result.rows.length === 0) {
                return res.status(404).json({
                    success: false,
                    message: 'Session not found or not owned by you.',
                });
            }

            res.json({ success: true, message: 'Session deleted.' });
        } catch (err) {
            console.error('Error deleting session:', err.message);
            res.status(500).json({ success: false, message: 'Failed to delete session.' });
        }
    });


    // ── POST /sessions/detail — upsert full SessionDetail with sub-lists ────────
    router.post('/detail', authenticate, async (req, res, next) => {
        const userId = req.user.id;
        const d = req.body;

        if (!d.session_start) {
            return res.status(400).json({ success: false, message: 'session_start is required.' });
        }

        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            // Upsert the session row
            const upsertResult = await client.query(
                `INSERT INTO cpr_sessions (
                user_id, mode, session_start, session_end,
                compression_count, correct_depth, correct_frequency,
                correct_recoil, depth_rate_combo, correct_posture,
                leaning_count, over_force_count, too_deep_count,
                average_depth, average_frequency, average_effective_depth,
                peak_depth, average_force, depth_consistency, freq_consistency,
                hands_on_ratio, no_flow_time, rate_variability,
                time_to_first_comp, consecutive_good_peak,
                fatigue_onset_index, ventilation_count, ventilation_compliance,
                pulse_checks_prompted, pulse_checks_complied,
                pulse_detected_final, patient_temperature,
                user_heart_rate, user_temperature,
                session_duration, total_grade, synced_from_local
            ) VALUES (
                $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,
                $18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,
                $33,$34,$35,$36,$37
            )
            ON CONFLICT (user_id, session_start) DO UPDATE SET
                mode = EXCLUDED.mode,
                session_end = EXCLUDED.session_end,
                compression_count = EXCLUDED.compression_count,
                correct_depth = EXCLUDED.correct_depth,
                correct_frequency = EXCLUDED.correct_frequency,
                correct_recoil = EXCLUDED.correct_recoil,
                depth_rate_combo = EXCLUDED.depth_rate_combo,
                correct_posture = EXCLUDED.correct_posture,
                leaning_count = EXCLUDED.leaning_count,
                over_force_count = EXCLUDED.over_force_count,
                too_deep_count = EXCLUDED.too_deep_count,
                average_depth = EXCLUDED.average_depth,
                average_frequency = EXCLUDED.average_frequency,
                average_effective_depth = EXCLUDED.average_effective_depth,
                peak_depth = EXCLUDED.peak_depth,
                average_force = EXCLUDED.average_force,
                depth_consistency = EXCLUDED.depth_consistency,
                freq_consistency = EXCLUDED.freq_consistency,
                hands_on_ratio = EXCLUDED.hands_on_ratio,
                no_flow_time = EXCLUDED.no_flow_time,
                rate_variability = EXCLUDED.rate_variability,
                time_to_first_comp = EXCLUDED.time_to_first_comp,
                consecutive_good_peak = EXCLUDED.consecutive_good_peak,
                fatigue_onset_index = EXCLUDED.fatigue_onset_index,
                ventilation_count = EXCLUDED.ventilation_count,
                ventilation_compliance = EXCLUDED.ventilation_compliance,
                pulse_checks_prompted = EXCLUDED.pulse_checks_prompted,
                pulse_checks_complied = EXCLUDED.pulse_checks_complied,
                pulse_detected_final = EXCLUDED.pulse_detected_final,
                patient_temperature = EXCLUDED.patient_temperature,
                user_heart_rate = EXCLUDED.user_heart_rate,
                user_temperature = EXCLUDED.user_temperature,
                session_duration = EXCLUDED.session_duration,
                total_grade = EXCLUDED.total_grade,
                synced_from_local = EXCLUDED.synced_from_local
            RETURNING id`,
                [
                    userId,
                    d.mode ?? 'emergency',
                    d.session_start,
                    d.session_end ?? null,
                    d.compression_count ?? 0,
                    d.correct_depth ?? 0,
                    d.correct_frequency ?? 0,
                    d.correct_recoil ?? 0,
                    d.depth_rate_combo ?? 0,
                    d.correct_posture ?? 0,
                    d.leaning_count ?? 0,
                    d.over_force_count ?? 0,
                    d.too_deep_count ?? 0,
                    d.average_depth ?? 0,
                    d.average_frequency ?? 0,
                    d.average_effective_depth ?? 0,
                    d.peak_depth ?? 0,
                    d.average_force ?? 0,
                    d.depth_consistency ?? 0,
                    d.freq_consistency ?? 0,
                    d.hands_on_ratio ?? 1,
                    d.no_flow_time ?? 0,
                    d.rate_variability ?? 0,
                    d.time_to_first_comp ?? 0,
                    d.consecutive_good_peak ?? 0,
                    d.fatigue_onset_index ?? 0,
                    d.ventilation_count ?? 0,
                    d.ventilation_compliance ?? 0,
                    d.pulse_checks_prompted ?? 0,
                    d.pulse_checks_complied ?? 0,
                    d.pulse_detected_final ?? false,
                    d.patient_temperature ?? null,
                    d.user_heart_rate ?? null,
                    d.user_temperature ?? null,
                    d.session_duration ?? 0,
                    d.total_grade ?? 0,
                    d.synced_from_local ?? false,
                ]
            );

            const sessionId = upsertResult.rows[0].id;

            // Delete existing sub-lists (idempotent re-upload)
            await client.query('DELETE FROM session_compressions WHERE session_id = $1', [sessionId]);
            await client.query('DELETE FROM session_ventilations WHERE session_id = $1', [sessionId]);
            await client.query('DELETE FROM session_pulse_checks WHERE session_id = $1', [sessionId]);
            await client.query('DELETE FROM session_rescuer_vitals WHERE session_id = $1', [sessionId]);

            await client.query(`
    ALTER TABLE cpr_sessions DROP CONSTRAINT IF EXISTS uq_user_session_start;
`);
            await client.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS uq_user_session_start
    ON cpr_sessions (user_id, session_start);
`);

            // Insert compressions
            const compressions = d.compressions ?? [];
            for (const c of compressions) {
                await client.query(
                    `INSERT INTO session_compressions
                 (session_id, timestamp_ms, depth, frequency, force,
                  recoil_achieved, over_force, posture_ok, leaning_detected,
                  wrist_alignment_angle, effective_depth)
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
                    [sessionId, c.ts, c.depth, c.freq, c.force ?? 0,
                        c.recoil ?? false, c.over_force ?? false,
                        c.posture_ok ?? false, c.leaning ?? false,
                        c.wrist_angle ?? 0, c.effective_depth ?? 0]
                );
            }

            // Insert ventilations
            const ventilations = d.ventilations ?? [];
            for (const v of ventilations) {
                await client.query(
                    `INSERT INTO session_ventilations
                 (session_id, timestamp_ms, cycle_number, ventilations_given, duration_sec, compliant)
                 VALUES ($1,$2,$3,$4,$5,$6)`,
                    [sessionId, v.ts, v.cycle_number, v.ventilations_given ?? 0,
                        v.duration_sec ?? 0, v.compliant ?? false]
                );
            }

            // Insert pulse checks
            const pulseChecks = d.pulse_checks ?? [];
            for (const p of pulseChecks) {
                await client.query(
                    `INSERT INTO session_pulse_checks
                 (session_id, timestamp_ms, interval_number, detected,
                  detected_bpm, confidence, perfusion_index, user_decision)
                 VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
                    [sessionId, p.ts, p.interval_number, p.detected ?? false,
                        p.detected_bpm ?? 0, p.confidence ?? 0,
                        p.perfusion_index ?? 0, p.user_decision ?? null]
                );
            }

            // Insert rescuer vitals
            const rescuerVitals = d.rescuer_vitals ?? [];
            for (const r of rescuerVitals) {
                await client.query(
                    `INSERT INTO session_rescuer_vitals
                 (session_id, timestamp_ms, heart_rate, spo2, temperature,
                  signal_quality, pause_type)
                 VALUES ($1,$2,$3,$4,$5,$6,$7)`,
                    [sessionId, r.ts, r.heart_rate ?? 0, r.spo2 ?? 0,
                        r.temperature ?? 0, r.signal_quality ?? 0,
                        r.pause_type ?? 'active']
                );
            }

            await client.query('COMMIT');
            res.json({ success: true, data: { id: sessionId } });

        } catch (err) {
            await client.query('ROLLBACK');
            console.error('Error saving session detail:', err.message);
            next(err);
        } finally {
            client.release();
        }
    });

    // ── GET /sessions/summary — paginated summary list ──────────────────────────
    router.get('/summary', authenticate, async (req, res) => {
        const userId = req.user.id;
        const limit = Math.min(parseInt(req.query.limit) || 20, 100);
        const offset = parseInt(req.query.offset) || 0;

        try {
            const result = await pool.query(
                `SELECT id, mode, compression_count, correct_depth, correct_frequency,
                    correct_recoil, depth_rate_combo, correct_posture,
                    average_depth, average_frequency, average_effective_depth,
                    peak_depth, leaning_count, over_force_count, too_deep_count,
                    hands_on_ratio, no_flow_time, fatigue_onset_index,
                    ventilation_count, ventilation_compliance,
                    pulse_checks_prompted, pulse_checks_complied, pulse_detected_final,
                    user_heart_rate, user_temperature, patient_temperature,
                    session_duration, total_grade, session_start, session_end, note
             FROM cpr_sessions
             WHERE user_id = $1
             ORDER BY session_start DESC
             LIMIT $2 OFFSET $3`,
                [userId, limit, offset]
            );

            const countResult = await pool.query(
                'SELECT COUNT(*) as total FROM cpr_sessions WHERE user_id = $1',
                [userId]
            );

            res.json({
                success: true,
                data: result.rows,
                meta: {
                    total: parseInt(countResult.rows[0].total),
                    limit,
                    offset,
                },
            });
        } catch (err) {
            console.error('Error fetching session summary:', err.message);
            res.status(500).json({ success: false, message: 'Failed to fetch sessions.' });
        }
    });

    // ── GET /sessions/:id/detail — full session with all sub-lists ──────────────
    // NOTE: this must be declared AFTER /summary to avoid route shadowing.
    router.get('/:id/detail', authenticate, async (req, res) => {
        const userId = req.user.id;
        const sessionId = parseInt(req.params.id);

        if (isNaN(sessionId)) {
            return res.status(400).json({ success: false, message: 'Invalid session ID.' });
        }

        try {
            const sessionResult = await pool.query(
                `SELECT * FROM cpr_sessions WHERE id = $1 AND user_id = $2`,
                [sessionId, userId]
            );

            if (sessionResult.rows.length === 0) {
                return res.status(404).json({ success: false, message: 'Session not found.' });
            }

            const session = sessionResult.rows[0];

            const [compressions, ventilations, pulseChecks, rescuerVitals] = await Promise.all([
                pool.query(
                    `SELECT timestamp_ms AS ts, depth, frequency, force,
                        recoil_achieved AS recoil, over_force, posture_ok,
                        leaning_detected AS leaning, wrist_alignment_angle AS wrist_angle,
                        effective_depth
                 FROM session_compressions WHERE session_id = $1 ORDER BY timestamp_ms`,
                    [sessionId]
                ),
                pool.query(
                    `SELECT timestamp_ms AS ts, cycle_number, ventilations_given,
                        duration_sec, compliant
                 FROM session_ventilations WHERE session_id = $1 ORDER BY timestamp_ms`,
                    [sessionId]
                ),
                pool.query(
                    `SELECT timestamp_ms AS ts, interval_number, detected,
                        detected_bpm, confidence, perfusion_index, user_decision
                 FROM session_pulse_checks WHERE session_id = $1 ORDER BY timestamp_ms`,
                    [sessionId]
                ),
                pool.query(
                    `SELECT timestamp_ms AS ts, heart_rate, spo2, temperature,
                        signal_quality, pause_type
                 FROM session_rescuer_vitals WHERE session_id = $1 ORDER BY timestamp_ms`,
                    [sessionId]
                ),
            ]);

            res.json({
                success: true,
                data: {
                    ...session,
                    compressions: compressions.rows,
                    ventilations: ventilations.rows,
                    pulse_checks: pulseChecks.rows,
                    rescuer_vitals: rescuerVitals.rows,
                },
            });
        } catch (err) {
            console.error('Error fetching session detail:', err.message);
            res.status(500).json({ success: false, message: 'Failed to fetch session detail.' });
        }
    });

    // ── PATCH /sessions/:id/note — update note only ─────────────────────────────
    router.patch('/:id/note', authenticate, async (req, res) => {
        const userId = req.user.id;
        const sessionId = parseInt(req.params.id);
        const { note } = req.body;

        if (isNaN(sessionId)) {
            return res.status(400).json({ success: false, message: 'Invalid session ID.' });
        }

        if (note !== null && note !== undefined && typeof note !== 'string') {
            return res.status(400).json({ success: false, message: 'Note must be a string or null.' });
        }

        if (note && note.length > 500) {
            return res.status(400).json({ success: false, message: 'Note must be 500 characters or fewer.' });
        }

        try {
            const result = await pool.query(
                `UPDATE cpr_sessions SET note = $1
             WHERE id = $2 AND user_id = $3
             RETURNING id, note`,
                [note ?? null, sessionId, userId]
            );

            if (result.rows.length === 0) {
                return res.status(404).json({ success: false, message: 'Session not found.' });
            }

            res.json({ success: true, data: result.rows[0] });
        } catch (err) {
            console.error('Error updating note:', err.message);
            res.status(500).json({ success: false, message: 'Failed to update note.' });
        }
    });

    return router;
};