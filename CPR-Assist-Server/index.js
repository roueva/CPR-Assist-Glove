require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { Pool } = require('pg');
const winston = require('winston');
const createAuthRoutes = require('./routes/auth');

// Create PostgreSQL connection pool
const pool = new Pool({
    user: process.env.POSTGRES_USER,
    host: process.env.POSTGRES_HOST,
    database: process.env.POSTGRES_DATABASE,
    password: process.env.POSTGRES_PASSWORD,
    port: process.env.POSTGRES_PORT,
});

pool.on('error', (err) => console.error('Unexpected error on idle client', err));

const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: 'error.log', level: 'error' }),
        new winston.transports.File({ filename: 'combined.log' })
    ]
});

const app = express();
app.use(cors());
app.use(helmet());
app.use(express.json());

// Global error handler
app.use((err, req, res, next) => {
    logger.error(err.message, { stack: err.stack });
    res.status(500).json({
        message: 'Internal server error',
        error: process.env.NODE_ENV === 'development' ? err.message : null
    });
});

// Pass pool to authRoutes and sessionRoutes
app.use('/auth', createAuthRoutes(pool));
const sessionRoutes = require('./routes/session');
app.use('/cpr', sessionRoutes(pool));

const PORT = process.env.PORT || 3000;
console.log(`Using port: ${PORT}`);

// Keep-alive ping every 10 seconds
setInterval(() => {
    console.log('Keep-alive ping');
}, 10000);

(async () => {
    try {
        // Test database connection before starting the server
        await pool.query('SELECT 1');
        console.log('Database connection successful');

        app.listen(PORT, '0.0.0.0', () => {
            console.log(`Server running on port ${PORT}`);
        });
    } catch (error) {
        console.error('Error during startup:', error.message);
        process.exit(1); // Exit with error code if something goes wrong
    }
})();
