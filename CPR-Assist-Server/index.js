require('dotenv').config(); // Ensure environment variables are loaded first

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { Pool } = require('pg');
const winston = require('winston');
const createAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed'); // ✅ Ensure it's imported as a function

// ✅ 1️⃣ PostgreSQL Connection Pool (Conditional SSL)
const pool = new Pool({
  user: process.env.POSTGRES_USER,
  host: process.env.POSTGRES_HOST,
  database: process.env.POSTGRES_DATABASE,
  password: String(process.env.POSTGRES_PASSWORD).trim(),
  port: process.env.POSTGRES_PORT || 5432,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

pool.on('error', (err) => console.error('Unexpected error on idle client', err));


// ✅ 2️⃣ Logging with Winston
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

// ✅ 3️⃣ Initialize Express with Middleware
const app = express();
app.use(helmet());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// ✅ 4️⃣ Enhanced CORS Configuration for Flutter + Railway
const corsOptions = {
  origin: '*', // Allow requests from all origins (set specific URL if needed)
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true, // For sessions or tokens
};
app.use(cors(corsOptions));
app.options('*', cors(corsOptions)); // Handle preflight requests

// ✅ 5️⃣ Health Check Route
app.get('/', (req, res) => {
    res.json({ message: '🚀 Server is running on Railway!', status: 'healthy' });
});

// ✅ 6️⃣ Google Maps API Key Route
app.get('/api/maps-key', (req, res) => {
    res.json({ apiKey: process.env.GOOGLE_MAPS_API_KEY });
});

// ✅ 7️⃣ Auth Routes
app.use('/auth', (req, res, next) => {
    req.db = pool; 
    next();
}, createAuthRoutes(pool));

// ✅ 8️⃣ Session Routes
app.use('/sessions', (req, res, next) => {
    req.db = pool;
    next();
}, createSessionRoutes(pool));

// ✅ 9️⃣ AED Routes
app.use('/aed', createAedRoutes(pool));

// ✅ 1️⃣0️⃣ Unknown Route Handler
app.use((req, res, next) => {
    res.status(404).json({ error: '❌ Route not found' });
});

// ✅ 1️⃣1️⃣ Global Error Handler
app.use((err, req, res, next) => {
    logger.error(err.message, { stack: err.stack });
    res.status(500).json({
        message: '❌ Internal server error',
        error: process.env.NODE_ENV === 'development' ? err.message : null
    });
});

// ✅ 1️⃣2️⃣ Start Server and Test Database Connection
const PORT = process.env.PORT || 3000;

(async () => {
    try {
        // Test database connection before starting the server
        await pool.query('SELECT 1');
        console.log('✅ Database connected successfully!');

        app.listen(PORT, '0.0.0.0', () => {
            console.log(`🚀 Server running on port ${PORT}`);
        });
    } catch (error) {
        console.error('❌ Error during startup:', error.message);
        process.exit(1);
    }
})();

// ✅ 1️⃣3️⃣ Graceful Shutdown
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
