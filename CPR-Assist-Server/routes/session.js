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

    return router;
};