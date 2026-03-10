const express = require('express');
const router = express.Router();
const createAuthController = require('../controllers/authController');
const { body, validationResult } = require('express-validator');

const {
    validateRegistrationInput,
    validateLoginInput,
    handleValidationErrors,
    authenticate,
} = require('../middleware/validation');

// Factory function to create routes with a specific pool
function initializeAuthRoutes(pool) {
    const authController = createAuthController(pool);

    // ✅ Test Route for "/auth"
    router.get('/test', (req, res) => {
     res.json({ message: '✅ Auth routes are working' });
    });


    // ✅ Log Incoming Requests to Auth.js
    router.use((req, res, next) => {
        console.log(`Received ${req.method} request on ${req.url}`);
  next();
    });



    // Registration route
    router.post(
        '/register',
        validateRegistrationInput,
        handleValidationErrors,
        (req, res, next) => authController.register(req, res, next)
    );

    // Login route
    router.post(
        '/login',
        validateLoginInput,
        handleValidationErrors,
        (req, res, next) => authController.login(req, res, next)
    );

    router.post('/refresh-token', (req, res, next) =>
        authController.refreshToken(req, res, next)
    );

    // Password reset request route
    router.post('/password-reset-request', (req, res, next) =>
        authController.requestPasswordReset(req, res, next)
    );

    // Password reset route
    router.post('/password-reset/:token', (req, res, next) =>
        authController.resetPassword(req, res, next)
    );

    // User profile route
    router.get('/profile', authenticate, async (req, res) => {
        try {
            const userId = req.user.id;
            const result = await pool.query(
                'SELECT id, username, email, created_at FROM users WHERE id = $1',
                [userId]
            );

            if (result.rows.length === 0) {
                return res.status(404).json({ success: false, message: 'User not found' });
            }

            res.json({
                success: true,
                data: result.rows[0],
            });
        } catch (error) {
            console.error('Error fetching profile:', error.message);
            res.status(500).json({
                success: false,
                message: 'Failed to fetch user profile',
                error: error.message,
            });
        }
    });


    router.put(
        '/profile',
        authenticate,
        [
            body('username')
                .trim()
                .isLength({ min: 3, max: 30 })
                .withMessage('Username must be between 3 and 30 characters')
                .matches(/^[a-zA-Z0-9_. ]+$/)
                .withMessage('Username can only contain letters, numbers, spaces, dots and underscores'),
        ],
        async (req, res) => {
            const errors = validationResult(req);
            if (!errors.isEmpty()) {
                return res.status(400).json({ success: false, errors: errors.array() });
            }

            const userId = req.user.id;
            const { username } = req.body;

            try {
                const existing = await pool.query(
                    'SELECT id FROM users WHERE username = $1 AND id != $2',
                    [username, userId]
                );
                if (existing.rows.length > 0) {
                    return res.status(409).json({ success: false, message: 'That username is already taken.' });
                }

                await pool.query('UPDATE users SET username = $1 WHERE id = $2', [username, userId]);
                res.json({ success: true, message: 'Profile updated.', username });
            } catch (err) {
                console.error('Error updating profile:', err.message);
                res.status(500).json({ success: false, message: 'Failed to update profile.' });
            }
        }
    );

    // Returns session count, average grade, best grade computed in DB.
    router.get('/stats', authenticate, async (req, res) => {
        const userId = req.user.id;
        try {
            const result = await pool.query(
                `SELECT
         COUNT(*)::int                             AS session_count,
         ROUND(AVG(total_grade)::numeric, 1)       AS average_grade,
         ROUND(MAX(total_grade)::numeric, 1)        AS best_grade,
         SUM(compression_count)::int               AS total_compressions,
         ROUND(AVG(average_depth)::numeric, 2)     AS avg_depth,
         ROUND(AVG(average_frequency)::numeric, 1) AS avg_frequency
       FROM cpr_sessions
       WHERE user_id = $1`,
                [userId]
            );

            const row = result.rows[0];
            res.json({
                success: true,
                data: {
                    session_count: row.session_count ?? 0,
                    average_grade: parseFloat(row.average_grade) || 0,
                    best_grade: parseFloat(row.best_grade) || 0,
                    total_compressions: row.total_compressions ?? 0,
                    avg_depth: parseFloat(row.avg_depth) || 0,
                    avg_frequency: parseFloat(row.avg_frequency) || 0,
                },
            });
        } catch (err) {
            console.error('Error fetching stats:', err.message);
            res.status(500).json({ success: false, message: 'Failed to fetch stats.' });
        }
    });

    return router;
}

module.exports = initializeAuthRoutes;
