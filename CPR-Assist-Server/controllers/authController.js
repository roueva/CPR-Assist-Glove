const { validationResult } = require('express-validator');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');

class AuthController {
    constructor(pool) {
        this.pool = pool;
    }

    // Register a new user
    async register(req, res, next) {
        const errors = validationResult(req);
        if (!errors.isEmpty()) {
            return res.status(400).json({ errors: errors.array() });
        }

        const { username, password, email } = req.body;

        try {
            const existingUser = await this.pool.query(
                'SELECT * FROM users WHERE username = $1 OR email = $2',
                [username, email]
            );

            if (existingUser.rows.length > 0) {
                return res.status(409).json({ error: 'A user with this information already exists' });
            }

            const hashedPassword = await bcrypt.hash(password, 12);

            await this.pool.query(
                'INSERT INTO users (username, password, email, created_at, is_active) VALUES ($1, $2, $3, NOW(), $4)',
                [username, hashedPassword, email, true]
            );

            res.status(201).json({ message: 'User registered successfully' });
        } catch (error) {
            console.error('Registration error:', error.message);
            next(error);
        }
    }


    // Login an existing user
    async login(req, res, next) {
        const { username, password } = req.body;

        try {
            const userResult = await this.pool.query(
                'SELECT id, username, password FROM users WHERE username = $1 AND is_active = true',
                [username]
            );

            if (userResult.rows.length === 0) {
                return res.status(401).json({ error: 'Invalid credentials' });
            }

            const user = userResult.rows[0];
            const isMatch = await bcrypt.compare(password, user.password);

            if (!isMatch) {
                return res.status(401).json({ error: 'Invalid credentials' });
            }

            // Include user ID in JWT
            const token = jwt.sign(
                { id: user.id, username: user.username }, // Include user ID
                process.env.JWT_SECRET,
                { expiresIn: '5y' }
            );

            // Send back the token and user ID
            res.json({
                message: 'Login successful',
                token,
                user_id: user.id,
            });
        } catch (error) {
            console.error('Login error:', error.message);
            next(error);
        }
    }

    // Refresh token
    async refreshToken(req, res, next) {
        try {
            const { token } = req.body;

            const decoded = jwt.verify(token, process.env.JWT_SECRET);

            const userResult = await this.pool.query(
                'SELECT * FROM users WHERE username = $1 AND is_active = true',
                [decoded.username]
            );

            if (userResult.rows.length === 0) {
                return res.status(401).json({ error: 'User not found or inactive' });
            }

            const newToken = jwt.sign(
                { id: decoded.id, username: decoded.username }, // Include user ID
                process.env.JWT_SECRET,
                { expiresIn: '5y' }
            );
            res.json({ token: newToken, user_id: decoded.id }); // Return both

        } catch (error) {
            console.error('Token refresh error:', error.message);
            res.status(401).json({ error: 'Invalid token' });
        }
    }

    // Request password reset
    async requestPasswordReset(req, res, next) {
        const { email } = req.body;

        try {
            const userResult = await this.pool.query(
                'SELECT * FROM users WHERE email = $1',
                [email]
            );

            if (userResult.rows.length === 0) {
                return res.status(404).json({ error: 'No user found with this email' });
            }

            const resetToken = crypto.randomBytes(32).toString('hex');
            const resetTokenExpiry = Date.now() + 3600000; // 1 hour

            await this.pool.query(
                'UPDATE users SET reset_token = $1, reset_token_expiry = $2 WHERE email = $3',
                [resetToken, resetTokenExpiry, email]
            );

            res.json({ message: 'Password reset token generated successfully' });
        } catch (error) {
            console.error('Password reset request error:', error.message);
            next(error);
        }
    }

    // Reset password
    async resetPassword(req, res, next) {
        const { token } = req.params;
        const { newPassword } = req.body;

        try {
            const userResult = await this.pool.query(
                'SELECT * FROM users WHERE reset_token = $1 AND reset_token_expiry > $2',
                [token, Date.now()]
            );

            if (userResult.rows.length === 0) {
                return res.status(400).json({ error: 'Invalid or expired reset token' });
            }

            const hashedPassword = await bcrypt.hash(newPassword, 12);

            await this.pool.query(
                'UPDATE users SET password = $1, reset_token = NULL, reset_token_expiry = NULL WHERE reset_token = $2',
                [hashedPassword, token]
            );

            res.json({ message: 'Password reset successful' });
        } catch (error) {
            console.error('Password reset error:', error.message);
            next(error);
        }
    }
}

module.exports = (pool) => new AuthController(pool);
