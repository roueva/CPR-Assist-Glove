const express = require('express');
const { body, validationResult } = require('express-validator');

module.exports = function (pool) {
    const router = express.Router();
    const { authenticate } = require('../middleware/validation'); // Import authenticate middleware

    router.post(
        '/summary',
        authenticate, // Ensures user is authenticated
        [
            body('compression_count').isInt().withMessage('Compression count must be an integer'),
            body('correct_depth').isInt().withMessage('Correct depth must be an integer'),
            body('correct_frequency').isInt().withMessage('Correct frequency must be an integer'),
            body('correct_angle').isFloat({ min: 0 }).withMessage('Correct angle must be a positive number'),
            body('session_duration').isInt().withMessage('Session duration must be an integer'),
        ],
        async (req, res, next) => {
            const errors = validationResult(req);
            if (!errors.isEmpty()) {
                return res.status(400).json({ errors: errors.array() });
            }

            // Extract user_id from authenticated user (set in req.user)
            const user_id = req.user.id;

            // Destructure other fields from the request body
            const {
                compression_count,
                correct_depth,
                correct_frequency,
                correct_angle,
                session_duration,
            } = req.body;

            try {
                // Insert session data into the database
                await pool.query(
                    `INSERT INTO cpr_sessions 
                    (user_id, compression_count, correct_depth, correct_frequency, correct_angle, session_duration, session_start, session_end)
                    VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())`,
                    [user_id, compression_count, correct_depth, correct_frequency, correct_angle, session_duration]
                );

                res.json({ message: 'Session summary saved successfully.' });
            } catch (err) {
                console.error('Error saving session summary:', err.message);
                next(err);
            }
        }
    );

    return router;
};
