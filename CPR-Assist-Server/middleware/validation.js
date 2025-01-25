const { body, validationResult } = require('express-validator');
const jwt = require('jsonwebtoken');

// Input validation for registration
const validateRegistrationInput = [
    body('username')
        .trim()
        .isAlphanumeric()
        .withMessage('Username must be alphanumeric')
        .isLength({ min: 3, max: 50 })
        .withMessage('Username must be between 3 and 50 characters'),
    body('email')
        .trim()
        .isEmail()
        .normalizeEmail()
        .withMessage('Must be a valid email'),
    body('password')
        .isLength({ min: 6 })
        .withMessage('Password must be at least 6 characters')
        .matches(/\d/)
        .withMessage('Password must contain a number')
        .matches(/[A-Z]/)
        .withMessage('Password must contain an uppercase letter'),
];

// Input validation for login
const validateLoginInput = [
    body('username')
        .trim()
        .notEmpty()
        .withMessage('Username is required'),
    body('password')
        .notEmpty()
        .withMessage('Password is required'),
];

// Input validation for session data
const validateSessionInput = [
    body('compression_count').isInt().withMessage('Compression count must be an integer'),
    body('correct_depth').isInt().withMessage('Correct depth must be an integer'),
    body('correct_frequency').isInt().withMessage('Correct frequency must be an integer'),
    body('correct_angle').isFloat({ min: 0 }).withMessage('Correct angle must be a positive number'),
    body('session_duration').isInt().withMessage('Session duration must be an integer'),
    body('correct_rebound').optional().isBoolean().withMessage('Correct rebound must be a boolean'),
    body('patient_heart_rate').optional().isInt().withMessage('Patient heart rate must be an integer'),
    body('patient_temperature').optional().isFloat().withMessage('Patient temperature must be a float'),
    body('user_heart_rate').optional().isInt().withMessage('User heart rate must be an integer'),
    body('user_temperature_rate').optional().isFloat().withMessage('User temperature rate must be a float'),
    body('session_start').optional().isISO8601().withMessage('Session start must be a valid date-time'),
    body('session_end').optional().isISO8601().withMessage('Session end must be a valid date-time'),
];

// Middleware to handle validation errors
const handleValidationErrors = (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
        return res.status(400).json({
            success: false,
            message: 'Validation failed',
            errors: errors.array(),
        });
    }
    next();
};

// JWT parsing helper
const parseToken = (header) => {
    if (!header) {
        throw new Error('Token missing');
    }
    if (!header.startsWith('Bearer ')) {
        throw new Error('Invalid token format');
    }
    return header.split(' ')[1];
};

// JWT authentication middleware
const authenticate = (req, res, next) => {
    try {
        const token = parseToken(req.header('Authorization'));
        const verified = jwt.verify(token, process.env.JWT_SECRET);
        req.user = verified;
        next();
    } catch (err) {
        res.status(401).json({
            success: false,
            message: 'Unauthorized access',
            error: err.message,
        });
    }
};

module.exports = {
    validateRegistrationInput,
    validateLoginInput,
    validateSessionInput,
    handleValidationErrors,
    authenticate,
};
