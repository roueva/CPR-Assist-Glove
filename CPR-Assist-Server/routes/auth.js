const express = require('express');
const router = express.Router();
const createAuthController = require('../controllers/authController');
const {
    validateRegistrationInput,
    validateLoginInput,
    handleValidationErrors,
    authenticate,
} = require('../middleware/validation');

// Create a pool reference outside the route handlers
let poolInstance;

// Middleware to attach database connection to all routes
router.use((req, res, next) => {
    req.db = poolInstance;
    next();
});

// Factory function to create routes with a specific pool
function initializeAuthRoutes(pool) {
    poolInstance = pool;
    const authController = createAuthController(pool);

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

    // Refresh token route
    router.post('/refresh-token', authenticate, (req, res, next) =>
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

    return router;
}

module.exports = initializeAuthRoutes;
