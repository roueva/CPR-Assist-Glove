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

// Input validation for session saving
const validateSessionInput = [
    body('duration_seconds')
        .isInt({ min: 0 })
        .withMessage('Duration must be a non-negative integer'),
    body('total_compressions')
        .isInt({ min: 0 })
        .withMessage('Total compressions must be a non-negative integer'),
    body('avg_depth_mm')
        .isFloat({ min: 0 })
        .withMessage('Average depth must be a non-negative number'),
    body('avg_rate_cpm')
        .isFloat({ min: 0 })
        .withMessage('Average rate must be a non-negative number'),
    body('correct_depth_percent')
        .isFloat({ min: 0, max: 100 })
        .withMessage('Correct depth percent must be between 0 and 100'),
    body('correct_rate_percent')
        .isFloat({ min: 0, max: 100 })
        .withMessage('Correct rate percent must be between 0 and 100'),
];

module.exports = {
    validateRegistrationInput,
    validateLoginInput,
    validateSessionInput,
    handleValidationErrors,
    authenticate,
};
