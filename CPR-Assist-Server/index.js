require('dotenv').config(); // Ensure environment variables are loaded first

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { Pool } = require('pg');
const winston = require('winston');
const createAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed'); // ✅ Ensure it's imported as a function


// Create PostgreSQL connection pool
const pool = new Pool({
    user: process.env.POSTGRES_USER,
    host: process.env.POSTGRES_HOST,
    database: process.env.POSTGRES_DATABASE,
    password: String(process.env.POSTGRES_PASSWORD).trim(), // ✅ Ensure it's a string
    port: process.env.POSTGRES_PORT || 5432,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

pool.on('error', (err) => console.error('Unexpected error on idle client', err));

// Create a Winston logger for application-wide logging
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


// ✅ Add Proper CORS Configuration
app.use(
  cors({
    origin: '*', // You can restrict to your Flutter app domain if needed
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  })
);


// Root route for health check
app.get('/', (req, res) => {
    res.json({ message: 'Server is running', status: 'healthy' });
});

app.get('/api/maps-key', (req, res) => {
    res.json({ apiKey: process.env.GOOGLE_MAPS_API_KEY });
});


// Register routes
app.use('/auth', (req, res, next) => {
    req.db = pool; // Attach pool to the request object for auth routes
    next();
}, createAuthRoutes(pool));

app.use('/sessions', (req, res, next) => {
    req.db = pool;
    next();
}, createSessionRoutes(pool));

app.use('/aed', createAedRoutes(pool)); // ✅ Correct: Call function and pass `pool`

// Handle unknown routes
app.use((req, res, next) => {
    res.status(404).json({ error: 'Route not found' });
});

// Global error handler
app.use((err, req, res, next) => {
    logger.error(err.message, { stack: err.stack });
    res.status(500).json({
        message: 'Internal server error',
        error: process.env.NODE_ENV === 'development' ? err.message : null
    });
});

const PORT = process.env.PORT || 3000;

(async () => {
    try {
        // Test database connection before starting the server
        await pool.query('SELECT 1');

        app.listen(PORT, '0.0.0.0', () => {
            console.log(`Server running on port ${PORT}`);
        });
    } catch (error) {
        console.error('Error during startup:', error.message);
        process.exit(1); // Exit with error code if something goes wrong
    }
})();

// Graceful shutdown
process.on('SIGTERM', async () => {
    console.log('SIGTERM received, closing pool...');
    await pool.end();
    console.log('Pool closed. Exiting process.');
    process.exit(0);
});

process.on('SIGINT', async () => {
    console.log('SIGINT received, closing pool...');
    await pool.end();
    console.log('Pool closed. Exiting process.');
    process.exit(0);
});
