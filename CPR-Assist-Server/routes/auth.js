const express = require('express');
const router = express.Router();
const createAuthController = require('../controllers/authController');
const { body, validationResult } = require('express-validator');
const bcrypt = require('bcrypt');

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
     res.json({ message: 'Auth routes are working' });
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
    router.post(
        '/password-reset/:token',
        [
            body('newPassword')
                .isLength({ min: 6 }).withMessage('Password must be at least 6 characters')
                .matches(/\d/).withMessage('Must contain a number')
                .matches(/[A-Z]/).withMessage('Must contain an uppercase letter'),
        ],
        handleValidationErrors,
        (req, res, next) => authController.resetPassword(req, res, next)
    );

    router.post('/forgot-username', async (req, res) => {
        const { email } = req.body;
        if (!email) {
            return res.status(400).json({ error: 'Email is required' });
        }
        try {
            const result = await pool.query(
                'SELECT username FROM users WHERE email = $1',
                [email]
            );
            // Always return 200 — don't confirm whether email is registered
            if (result.rows.length > 0) {
                const { sendUsernameReminderEmail } = require('../services/emailService');
                await sendUsernameReminderEmail(email, result.rows[0].username);
            }
            res.json({ message: 'If an account exists with that email, your username has been sent.' });
        } catch (err) {
            console.error('Forgot username error:', err.message);
            res.status(500).json({ error: 'Failed to process request.' });
        }
    });

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
                .matches(/^[a-zA-Z0-9_.]+$/)
                .withMessage('Username can only contain letters, numbers, underscores and dots')
                .isLength({ min: 3, max: 50 })
                .withMessage('Username must be between 3 and 50 characters'),
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
   COUNT(*)::int                                                        AS session_count,
   SUM(CASE WHEN mode IN ('training','training_no_feedback') THEN 1 ELSE 0 END)::int
                                                                        AS training_count,
   SUM(CASE WHEN mode = 'emergency' THEN 1 ELSE 0 END)::int            AS emergency_count,
   ROUND(
     AVG(CASE WHEN mode IN ('training','training_no_feedback') AND total_grade > 0
              THEN total_grade END)::numeric, 1)                        AS average_grade,
   ROUND(
     MAX(CASE WHEN mode IN ('training','training_no_feedback') AND total_grade > 0
              THEN total_grade END)::numeric, 1)                        AS best_grade,
   SUM(compression_count)::int                                          AS total_compressions,
   ROUND(AVG(average_depth)::numeric, 2)                                AS avg_depth,
   ROUND(AVG(average_frequency)::numeric, 1)                            AS avg_frequency
 FROM cpr_sessions
 WHERE user_id = $1`,
                [userId]
            );

            const row = result.rows[0];
            res.json({
                success: true,
                data: {
                    session_count: row.session_count ?? 0,
                    training_count: row.training_count ?? 0,
                    emergency_count: row.emergency_count ?? 0,
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

    router.put(
        '/change-password',
        authenticate,
        [
            body('currentPassword').notEmpty().withMessage('Current password is required'),
            body('newPassword')
                .isLength({ min: 6 }).withMessage('At least 6 characters')
                .matches(/\d/).withMessage('Must contain a number')
                .matches(/[A-Z]/).withMessage('Must contain an uppercase letter'),
        ],
        handleValidationErrors,
        async (req, res) => {
            const { currentPassword, newPassword } = req.body;
            const userId = req.user.id;
            try {
                const result = await pool.query(
                    'SELECT password FROM users WHERE id = $1',
                    [userId]
                );
                if (result.rows.length === 0) {
                    return res.status(404).json({ success: false, message: 'User not found.' });
                }
                const isMatch = await bcrypt.compare(currentPassword, result.rows[0].password);
                if (!isMatch) {
                    return res.status(401).json({ success: false, message: 'Current password is incorrect.' });
                }
                const hashed = await bcrypt.hash(newPassword, 12);
                await pool.query('UPDATE users SET password = $1 WHERE id = $2', [hashed, userId]);
                res.json({ success: true, message: 'Password changed successfully.' });
            } catch (err) {
                console.error('Change password error:', err.message);
                res.status(500).json({ success: false, message: 'Failed to change password.' });
            }
        }
    );

    // Delete account — removes user and cascades to all sessions
    router.delete('/account', authenticate, async (req, res) => {
        try {
            const userId = req.user.id;
            const result = await pool.query(
                'DELETE FROM users WHERE id = $1 RETURNING id',
                [userId]
            );
            if (result.rowCount === 0) {
                return res.status(404).json({ success: false, message: 'User not found.' });
            }
            res.json({ success: true, message: 'Account deleted.' });
        } catch (err) {
            console.error('Delete account error:', err.message);
            res.status(500).json({ success: false, message: 'Failed to delete account.' });
        }
    });

    return router;
}

module.exports = initializeAuthRoutes;
