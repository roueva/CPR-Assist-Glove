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
            body('correct_angle').isFloat({ min: 0 }).withMessage('Correct angle must be a positive number'),
            body('correct_rebound').optional().isBoolean().withMessage('Correct rebound must be a boolean'),
            body('patient_heart_rate').optional().isInt().withMessage('Patient heart rate must be an integer'),
            body('patient_temperature').optional().isFloat().withMessage('Patient temperature must be a float'),
            body('user_heart_rate').optional().isInt().withMessage('User heart rate must be an integer'),
            body('user_temperature_rate').optional().isFloat().withMessage('User temperature rate must be a float'),
            body('session_duration').isInt().withMessage('Session duration must be an integer'),
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
                correct_angle,
                correct_rebound,
                patient_heart_rate,
                patient_temperature,
                user_heart_rate,
                user_temperature_rate,
                session_duration,
            } = req.body;

            try {
                await pool.query(
                    `INSERT INTO cpr_sessions 
                    (user_id, compression_count, correct_depth, correct_frequency, correct_angle, correct_rebound, 
                     patient_heart_rate, patient_temperature, user_heart_rate, user_temperature_rate, session_duration, 
                     session_start, session_end)
                    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW(), NOW())`,
                    [
                        user_id,
                        compression_count,
                        correct_depth,
                        correct_frequency,
                        correct_angle,
                        correct_rebound,
                        patient_heart_rate,
                        patient_temperature,
                        user_heart_rate,
                        user_temperature_rate,
                        session_duration,
                    ]
                );

                res.json({ message: 'Session summary saved successfully.' });
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
                `SELECT id, compression_count, correct_depth, correct_frequency, correct_angle, correct_rebound, 
                        patient_heart_rate, patient_temperature, user_heart_rate, user_temperature_rate, session_duration, 
                        session_start, session_end
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

    return router;
};
