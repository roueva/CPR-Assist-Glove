const express = require('express');
const { body, validationResult } = require('express-validator');

// ─────────────────────────────────────────────────────────────────────────────
// SESSION ROUTES  —  CPR Assist Backend  v3.0
//
// Routes:
//   POST   /sessions/summary          — legacy summary-only save (kept for compat)
//   GET    /sessions/summaries        — legacy list (kept for compat, Flutter still uses it)
//   GET    /sessions/best             — single best Training session for leaderboard card
//   DELETE /sessions/all              — delete all sessions for current user
//   DELETE /sessions/:id              — delete one session
//   POST   /sessions/detail           — upsert full SessionDetail with all sub-lists
//   GET    /sessions/summary          — paginated summary list (current primary list endpoint)
//   GET    /sessions/:id/detail       — full session + all sub-lists (MUST be last)
//   PATCH  /sessions/:id/note         — update note only
//
// Rules:
//   - Emergency sessions always have total_grade = 0 — enforced server-side
//   - average_force is NOT stored — internal metric only
//   - user_heart_rate is FLOAT (was INT, migration in db.js)
// ─────────────────────────────────────────────────────────────────────────────

const VALID_MODES = ['emergency', 'training', 'training_no_feedback'];
const VALID_SCENARIOS = ['standard_adult', 'standard_adult_nofeedback', 'pediatric', 'timed_endurance'];

module.exports = function (pool) {
    const router = express.Router();
    const { authenticate } = require('../middleware/validation');

    // ── POST /sessions/summary — legacy summary-only save ────────────────────
    // Kept for backward compatibility. New code should use POST /sessions/detail.
    router.post(
        '/summary',
        authenticate,
        [
            body('compression_count').isInt({ min: 0 }).withMessage('compression_count must be a non-negative integer'),
            body('correct_depth').isInt({ min: 0 }).withMessage('correct_depth must be a non-negative integer'),
            body('correct_frequency').isInt({ min: 0 }).withMessage('correct_frequency must be a non-negative integer'),
            body('session_duration').isInt({ min: 0 }).withMessage('session_duration must be a non-negative integer'),
            body('correct_recoil').optional().isInt({ min: 0 }).withMessage('correct_recoil must be a non-negative integer'),
            body('depth_rate_combo').optional().isInt({ min: 0 }).withMessage('depth_rate_combo must be a non-negative integer'),
            body('average_depth').optional().isFloat({ min: 0 }).withMessage('average_depth must be a non-negative number'),
            body('average_frequency').optional().isFloat({ min: 0 }).withMessage('average_frequency must be a non-negative number'),
            body('total_grade').optional().isFloat({ min: 0, max: 100 }).withMessage('total_grade must be 0–100'),
            body('session_start').optional().isISO8601().withMessage('session_start must be a valid ISO date'),
            body('mode').optional().isIn(VALID_MODES).withMessage('invalid mode'),
            body('patient_temperature').optional().isFloat().withMessage('patient_temperature must be a float'),
            body('user_heart_rate').optional().isFloat().withMessage('user_heart_rate must be a number'),
            body('user_temperature').optional().isFloat().withMessage('user_temperature must be a float'),
        ],
        async (req, res, next) => {
            const errors = validationResult(req);
            if (!errors.isEmpty()) {
                return res.status(400).json({ success: false, errors: errors.array() });
            }

            const userId = req.user.id;
            const {
                compression_count,
                correct_depth,
                correct_frequency,
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
                mode,
            } = req.body;

            const resolvedMode = mode ?? 'emergency';
            // Emergency sessions never have a grade
            const resolvedGrade = (resolvedMode === 'emergency') ? 0 : (total_grade ?? 0);

            try {
                await pool.query(
                    `INSERT INTO cpr_sessions
                     (user_id, mode, compression_count, correct_depth, correct_frequency,
                      correct_recoil, depth_rate_combo, average_depth, average_frequency,
                      patient_temperature, user_heart_rate, user_temperature,
                      session_duration, total_grade, session_start, session_end)
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,NOW())`,
                    [
                        userId,
                        resolvedMode,
                        compression_count,
                        correct_depth,
                        correct_frequency,
                        correct_recoil ?? 0,
                        depth_rate_combo ?? 0,
                        average_depth ?? 0.0,
                        average_frequency ?? 0.0,
                        patient_temperature ?? null,
                        user_heart_rate ?? null,
                        user_temperature ?? null,
                        session_duration,
                        resolvedGrade,
                        session_start ?? new Date().toISOString(),
                    ]
                );
                res.json({ success: true, message: 'Session summary saved.' });
            } catch (err) {
                console.error('Error saving session summary:', err.message);
                next(err);
            }
        }
    );

    // ── GET /sessions/summaries — legacy list (Flutter session_provider.dart) ─
    // Returns enough fields for the summary cards. Kept as-is route name for
    // Flutter compat; updated SELECT to include new v3.0 fields.
    router.get('/summaries', authenticate, async (req, res) => {
        try {
            const userId = req.user.id;
            const result = await pool.query(
                `SELECT id, mode, scenario,
            compression_count, correct_depth, correct_frequency,
            correct_recoil, depth_rate_combo, correct_posture,
            average_depth, average_frequency, average_effective_depth,
            peak_depth, depth_sd, depth_consistency, freq_consistency,
            leaning_count, over_force_count, too_deep_count,
            no_flow_intervals, rescuer_swap_count,
            hands_on_ratio, no_flow_time, fatigue_onset_index,
            ventilation_count, ventilation_compliance, correct_ventilations,
            pulse_checks_prompted, pulse_checks_complied, pulse_detected_final,
            rescuer_hr_last_pause, rescuer_spo2_last_pause,
            patient_temperature, ambient_temp_start, ambient_temp_end,
            session_duration, total_grade,
            session_start, session_end, note,
            ROW_NUMBER() OVER (ORDER BY session_start ASC) AS session_number
     FROM cpr_sessions
     WHERE user_id = $1
     ORDER BY session_start DESC
     LIMIT $2 OFFSET $3`,
                [userId, limit, offset]
            );
            res.json({ success: true, data: result.rows });
        } catch (err) {
            console.error('Error fetching session summaries:', err.message);
            res.status(500).json({ success: false, message: 'Failed to fetch session summaries.' });
        }
    });

    // ── GET /sessions/best — best Training session for leaderboard card ───────
    // Only returns Training sessions — Emergency sessions have no grade.
    router.get('/best', authenticate, async (req, res) => {
        const userId = req.user.id;
        try {
            const result = await pool.query(
                `SELECT id, mode, scenario,
                        compression_count, correct_depth, correct_frequency,
                        correct_recoil, depth_rate_combo, average_depth, average_frequency,
                        peak_depth, session_duration, total_grade, session_start, session_end
                 FROM cpr_sessions
                 WHERE user_id = $1
                   AND mode IN ('training', 'training_no_feedback')
                   AND total_grade > 0
                 ORDER BY total_grade DESC
                 LIMIT 1`,
                [userId]
            );
            res.json({ success: true, data: result.rows[0] ?? null });
        } catch (err) {
            console.error('Error fetching best session:', err.message);
            res.status(500).json({ success: false, message: 'Failed to fetch best session.' });
        }
    });

    // ── DELETE /sessions/all — delete all sessions for current user ───────────
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



    // ── DELETE /sessions/:id — delete one session ─────────────────────────────
    router.delete('/:id', authenticate, async (req, res) => {
        const userId = req.user.id;
        const sessionId = parseInt(req.params.id);
        if (isNaN(sessionId)) {
            return res.status(400).json({ success: false, message: 'Invalid session ID.' });
        }
        try {
            const result = await pool.query(
                'DELETE FROM cpr_sessions WHERE id = $1 AND user_id = $2 RETURNING id',
                [sessionId, userId]
            );
            if (result.rows.length === 0) {
                return res.status(404).json({ success: false, message: 'Session not found or not owned by you.' });
            }
            res.json({ success: true, message: 'Session deleted.' });
        } catch (err) {
            console.error('Error deleting session:', err.message);
            res.status(500).json({ success: false, message: 'Failed to delete session.' });
        }
    });

    // ── POST /sessions/detail — upsert full SessionDetail with all sub-lists ──
    //
    // Idempotent: ON CONFLICT (user_id, session_start) updates the session row
    // and replaces all sub-lists. Safe to call multiple times for the same session.
    //
    // Sub-list JSON key mapping (matches CompressionEvent.toJson() etc.):
    //   compressions[]   : ts, depth, freq, instantaneous_rate, force, recoil,
    //                      over_force, posture_ok, leaning, wrist_angle,
    //                      wrist_flexion, axis_dev, effective_depth,
    //                      peak_force, downstroke_time_ms
    //   ventilations[]   : ts, cycle_number, ventilations_given, duration_sec, compliant
    //   pulse_checks[]   : ts, interval_number, classification, detected,
    //                      detected_bpm, confidence, perfusion_index,
    //                      detector_a_count, detector_b_count, user_decision
    //   rescuer_vitals[] : ts, heart_rate, spo2, rmssd, rescuer_pi,
    //                      temperature, fatigue_score, signal_quality, pause_type
    router.post('/detail', authenticate, async (req, res, next) => {
        const userId = req.user.id;
        const d = req.body;

        // ── Input validation ───────────────────────────────────────────────────
        if (!d.session_start) {
            return res.status(400).json({ success: false, message: 'session_start is required.' });
        }

        const resolvedMode = d.mode ?? 'emergency';
        if (!VALID_MODES.includes(resolvedMode)) {
            return res.status(400).json({ success: false, message: `Invalid mode. Must be one of: ${VALID_MODES.join(', ')}` });
        }

        const resolvedScenario = d.scenario ?? 'standard_adult';
        if (!VALID_SCENARIOS.includes(resolvedScenario)) {
            return res.status(400).json({ success: false, message: `Invalid scenario. Must be one of: ${VALID_SCENARIOS.join(', ')}` });
        }

        if (d.compression_count !== undefined && (typeof d.compression_count !== 'number' || d.compression_count < 0)) {
            return res.status(400).json({ success: false, message: 'compression_count must be a non-negative number.' });
        }

        // Emergency sessions never have a grade — enforce server-side
        const resolvedGrade = (resolvedMode === 'emergency') ? 0 : (d.total_grade ?? 0);

        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            // ── Ensure unique index exists (idempotent) ────────────────────────
            // Done here rather than in db.js to ensure it exists even on fresh deploys.
            await client.query(`
                CREATE UNIQUE INDEX IF NOT EXISTS uq_user_session_start
                ON cpr_sessions (user_id, session_start)
            `);

            // ── Upsert the session row ─────────────────────────────────────────
            const upsertResult = await client.query(
                `INSERT INTO cpr_sessions (
                    user_id, mode, scenario, session_start, session_end,
                    compression_count, correct_depth, correct_frequency,
                    correct_recoil, depth_rate_combo, correct_posture,
                    leaning_count, over_force_count, too_deep_count,
                    average_depth, average_frequency, average_effective_depth,
                    peak_depth, depth_sd, depth_consistency, freq_consistency,
                    hands_on_ratio, no_flow_time, no_flow_intervals,
                    rate_variability, time_to_first_comp, consecutive_good_peak,
                    fatigue_onset_index, rescuer_swap_count,
                    ventilation_count, ventilation_compliance, correct_ventilations,
                    pulse_checks_prompted, pulse_checks_complied, pulse_detected_final,
                    patient_temperature, rescuer_hr_last_pause, rescuer_spo2_last_pause,
                    ambient_temp_start, ambient_temp_end,
                    user_heart_rate, user_temperature,
                    session_duration, total_grade, synced_from_local
                ) VALUES (
                    $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,
                    $18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,
                    $33,$34,$35,$36,$37,$38,$39,$40,$41,$42,$43,$44,$45
                )
                ON CONFLICT (user_id, session_start) DO UPDATE SET
                    mode                   = EXCLUDED.mode,
                    scenario               = EXCLUDED.scenario,
                    session_end            = EXCLUDED.session_end,
                    compression_count      = EXCLUDED.compression_count,
                    correct_depth          = EXCLUDED.correct_depth,
                    correct_frequency      = EXCLUDED.correct_frequency,
                    correct_recoil         = EXCLUDED.correct_recoil,
                    depth_rate_combo       = EXCLUDED.depth_rate_combo,
                    correct_posture        = EXCLUDED.correct_posture,
                    leaning_count          = EXCLUDED.leaning_count,
                    over_force_count       = EXCLUDED.over_force_count,
                    too_deep_count         = EXCLUDED.too_deep_count,
                    average_depth          = EXCLUDED.average_depth,
                    average_frequency      = EXCLUDED.average_frequency,
                    average_effective_depth = EXCLUDED.average_effective_depth,
                    peak_depth             = EXCLUDED.peak_depth,
                    depth_sd               = EXCLUDED.depth_sd,
                    depth_consistency      = EXCLUDED.depth_consistency,
                    freq_consistency       = EXCLUDED.freq_consistency,
                    hands_on_ratio         = EXCLUDED.hands_on_ratio,
                    no_flow_time           = EXCLUDED.no_flow_time,
                    no_flow_intervals      = EXCLUDED.no_flow_intervals,
                    rate_variability       = EXCLUDED.rate_variability,
                    time_to_first_comp     = EXCLUDED.time_to_first_comp,
                    consecutive_good_peak  = EXCLUDED.consecutive_good_peak,
                    fatigue_onset_index    = EXCLUDED.fatigue_onset_index,
                    rescuer_swap_count     = EXCLUDED.rescuer_swap_count,
                    ventilation_count      = EXCLUDED.ventilation_count,
                    ventilation_compliance = EXCLUDED.ventilation_compliance,
                    correct_ventilations   = EXCLUDED.correct_ventilations,
                    pulse_checks_prompted  = EXCLUDED.pulse_checks_prompted,
                    pulse_checks_complied  = EXCLUDED.pulse_checks_complied,
                    pulse_detected_final   = EXCLUDED.pulse_detected_final,
                    patient_temperature    = EXCLUDED.patient_temperature,
                    rescuer_hr_last_pause  = EXCLUDED.rescuer_hr_last_pause,
                    rescuer_spo2_last_pause = EXCLUDED.rescuer_spo2_last_pause,
                    ambient_temp_start     = EXCLUDED.ambient_temp_start,
                    ambient_temp_end       = EXCLUDED.ambient_temp_end,
                    user_heart_rate        = EXCLUDED.user_heart_rate,
                    user_temperature       = EXCLUDED.user_temperature,
                    session_duration       = EXCLUDED.session_duration,
                    total_grade            = EXCLUDED.total_grade,
                    synced_from_local      = EXCLUDED.synced_from_local
                RETURNING id`,
                [
                    userId,                            // $1
                    resolvedMode,                      // $2
                    resolvedScenario,                  // $3
                    d.session_start,                   // $4
                    d.session_end ?? null,  // $5
                    d.compression_count ?? 0,     // $6
                    d.correct_depth ?? 0,     // $7
                    d.correct_frequency ?? 0,     // $8
                    d.correct_recoil ?? 0,     // $9
                    d.depth_rate_combo ?? 0,     // $10
                    d.correct_posture ?? 0,     // $11
                    d.leaning_count ?? 0,     // $12
                    d.over_force_count ?? 0,     // $13
                    d.too_deep_count ?? 0,     // $14
                    d.average_depth ?? 0,     // $15
                    d.average_frequency ?? 0,     // $16
                    d.average_effective_depth ?? 0,    // $17
                    d.peak_depth ?? 0,     // $18
                    d.depth_sd ?? 0,     // $19
                    d.depth_consistency ?? 0,     // $20
                    d.freq_consistency ?? 0,     // $21
                    d.hands_on_ratio ?? 1,     // $22
                    d.no_flow_time ?? 0,     // $23
                    d.no_flow_intervals ?? 0,     // $24
                    d.rate_variability ?? 0,     // $25
                    d.time_to_first_comp ?? 0,     // $26
                    d.consecutive_good_peak ?? 0,     // $27
                    d.fatigue_onset_index ?? 0,     // $28
                    d.rescuer_swap_count ?? 0,     // $29
                    d.ventilation_count ?? 0,     // $30
                    d.ventilation_compliance ?? 0,     // $31
                    d.correct_ventilations ?? 0,     // $32
                    d.pulse_checks_prompted ?? 0,     // $33
                    d.pulse_checks_complied ?? 0,     // $34
                    d.pulse_detected_final ?? false, // $35
                    d.patient_temperature ?? null,  // $36
                    d.rescuer_hr_last_pause ?? null,  // $37
                    d.rescuer_spo2_last_pause ?? null, // $38
                    d.ambient_temp_start ?? null,  // $39
                    d.ambient_temp_end ?? null,  // $40
                    d.user_heart_rate ?? null,  // $41
                    d.user_temperature ?? null,  // $42
                    d.session_duration ?? 0,     // $43
                    resolvedGrade,                     // $44
                    d.synced_from_local ?? false, // $45
                ]
            );

            const sessionId = upsertResult.rows[0].id;

            // ── Replace all sub-lists (idempotent re-upload) ──────────────────
            await client.query('DELETE FROM session_compressions  WHERE session_id = $1', [sessionId]);
            await client.query('DELETE FROM session_ventilations  WHERE session_id = $1', [sessionId]);
            await client.query('DELETE FROM session_pulse_checks  WHERE session_id = $1', [sessionId]);
            await client.query('DELETE FROM session_rescuer_vitals WHERE session_id = $1', [sessionId]);

            // ── Insert compressions ───────────────────────────────────────────
            const compressions = d.compressions ?? [];
            for (const c of compressions) {
                await client.query(
                    `INSERT INTO session_compressions
                     (session_id, timestamp_ms, depth, frequency, instantaneous_rate,
                      force, recoil_achieved, over_force, posture_ok, leaning_detected,
                      wrist_alignment_angle, wrist_flexion_angle, compression_axis_dev,
                      effective_depth, peak_force, downstroke_time_ms)
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`,
                    [
                        sessionId,
                        c.ts,
                        c.depth,
                        c.freq ?? 0,
                        c.instantaneous_rate ?? 0,
                        c.force ?? 0,
                        c.recoil ?? false,
                        c.over_force ?? false,
                        c.posture_ok ?? false,
                        c.leaning ?? false,
                        c.wrist_angle ?? 0,
                        c.wrist_flexion ?? 0,
                        c.axis_dev ?? 0,
                        c.effective_depth ?? 0,
                        c.peak_force ?? 0,
                        c.downstroke_time_ms ?? 0,
                    ]
                );
            }

            // ── Insert ventilations ───────────────────────────────────────────
            const ventilations = d.ventilations ?? [];
            for (const v of ventilations) {
                await client.query(
                    `INSERT INTO session_ventilations
                     (session_id, timestamp_ms, cycle_number,
                      ventilations_given, duration_sec, compliant)
                     VALUES ($1,$2,$3,$4,$5,$6)`,
                    [
                        sessionId,
                        v.ts,
                        v.cycle_number,
                        v.ventilations_given ?? 0,
                        v.duration_sec ?? 0,
                        v.compliant ?? false,
                    ]
                );
            }

            // ── Insert pulse checks ───────────────────────────────────────────
            const pulseChecks = d.pulse_checks ?? [];
            for (const p of pulseChecks) {
                await client.query(
                    `INSERT INTO session_pulse_checks
                     (session_id, timestamp_ms, interval_number,
                      classification, detected, detected_bpm, confidence,
                      perfusion_index, detector_a_count, detector_b_count,
                      user_decision)
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
                    [
                        sessionId,
                        p.ts,
                        p.interval_number,
                        p.classification ?? 0,
                        p.detected ?? false,
                        p.detected_bpm ?? 0,
                        p.confidence ?? 0,
                        p.perfusion_index ?? 0,
                        p.detector_a_count ?? 0,
                        p.detector_b_count ?? 0,
                        p.user_decision ?? null,
                    ]
                );
            }

            // ── Insert rescuer vitals ─────────────────────────────────────────
            const rescuerVitals = d.rescuer_vitals ?? [];
            for (const r of rescuerVitals) {
                await client.query(
                    `INSERT INTO session_rescuer_vitals
                     (session_id, timestamp_ms, heart_rate, spo2, rmssd,
                      rescuer_pi, temperature, fatigue_score,
                      signal_quality, pause_type)
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
                    [
                        sessionId,
                        r.ts,
                        r.heart_rate ?? 0,
                        r.spo2 ?? 0,
                        r.rmssd ?? 0,
                        r.rescuer_pi ?? 0,
                        r.temperature ?? 0,
                        r.fatigue_score ?? 0,
                        r.signal_quality ?? 0,
                        r.pause_type ?? 'active',
                    ]
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

    // ── GET /sessions/summary — paginated summary list ────────────────────────
    // Primary endpoint for the session history screen and session list views.
    // Returns all summary-level fields needed to render a card without fetching detail.
    router.get('/summary', authenticate, async (req, res) => {
        const userId = req.user.id;
        const limit = Math.min(parseInt(req.query.limit) || 20, 100);
        const offset = parseInt(req.query.offset) || 0;

        try {
            const result = await pool.query(
                `SELECT id, mode, scenario,
            compression_count, correct_depth, correct_frequency,
            correct_recoil, depth_rate_combo, correct_posture,
            average_depth, average_frequency, average_effective_depth,
            peak_depth, depth_sd, depth_consistency, freq_consistency,
            leaning_count, over_force_count, too_deep_count,
            no_flow_intervals, rescuer_swap_count,
            hands_on_ratio, no_flow_time, fatigue_onset_index,
            ventilation_count, ventilation_compliance, correct_ventilations,
            pulse_checks_prompted, pulse_checks_complied, pulse_detected_final,
            rescuer_hr_last_pause, rescuer_spo2_last_pause,
            patient_temperature, ambient_temp_start, ambient_temp_end,
            session_duration, total_grade,
            session_start, session_end, note,
            ROW_NUMBER() OVER (ORDER BY session_start ASC) AS session_number
     FROM cpr_sessions
     WHERE user_id = $1
     ORDER BY session_start DESC
     LIMIT $2 OFFSET $3`,
                [userId, limit, offset]
            );

            const countResult = await pool.query(
                'SELECT COUNT(*) AS total FROM cpr_sessions WHERE user_id = $1',
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


    // ── GET /sessions/:id/detail — full session + all sub-lists ──────────────
    // MUST be declared last to avoid shadowing /summary, /summaries, /best.
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
                    `SELECT timestamp_ms        AS ts,
                            depth,
                            frequency,
                            instantaneous_rate,
                            force,
                            recoil_achieved     AS recoil,
                            over_force,
                            posture_ok,
                            leaning_detected    AS leaning,
                            wrist_alignment_angle AS wrist_angle,
                            wrist_flexion_angle   AS wrist_flexion,
                            compression_axis_dev  AS axis_dev,
                            effective_depth,
                            peak_force,
                            downstroke_time_ms
                     FROM session_compressions
                     WHERE session_id = $1
                     ORDER BY timestamp_ms`,
                    [sessionId]
                ),
                pool.query(
                    `SELECT timestamp_ms      AS ts,
                            cycle_number,
                            ventilations_given,
                            duration_sec,
                            compliant
                     FROM session_ventilations
                     WHERE session_id = $1
                     ORDER BY timestamp_ms`,
                    [sessionId]
                ),
                pool.query(
                    `SELECT timestamp_ms    AS ts,
                            interval_number,
                            classification,
                            detected,
                            detected_bpm,
                            confidence,
                            perfusion_index,
                            detector_a_count,
                            detector_b_count,
                            user_decision
                     FROM session_pulse_checks
                     WHERE session_id = $1
                     ORDER BY timestamp_ms`,
                    [sessionId]
                ),
                pool.query(
                    `SELECT timestamp_ms   AS ts,
                            heart_rate,
                            spo2,
                            rmssd,
                            rescuer_pi,
                            temperature,
                            fatigue_score,
                            signal_quality,
                            pause_type
                     FROM session_rescuer_vitals
                     WHERE session_id = $1
                     ORDER BY timestamp_ms`,
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

    // ── PATCH /sessions/:id/note — update note only ───────────────────────────
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