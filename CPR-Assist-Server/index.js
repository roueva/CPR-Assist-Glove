require('dotenv').config(); // Load environment variables

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { Pool } = require('pg');
const winston = require('winston');
const createAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed');

// ✅ 1️⃣ PostgreSQL Connection Pool
const pool = new Pool({
    user: process.env.POSTGRES_USER,
    host: process.env.POSTGRES_HOST,
    database: process.env.POSTGRES_DATABASE,
    password: String(process.env.POSTGRES_PASSWORD).trim(),
    port: process.env.POSTGRES_PORT || 5432,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

pool.on('error', (err) => console.error('Unexpected error on idle client', err));

// ✅ 2️⃣ Winston Logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [
        new winston.transports.File({ filename: 'error.log', level: 'error' }),
        new winston.transports.File({ filename: 'combined.log' }),
        new winston.transports.Console(), // ✅ Show logs in Railway dashboard
    ],
});

// ✅ 3️⃣ Express App Setup
const app = express();
app.use(helmet());
app.use(express.json());

// ✅ 4️⃣ CORS Configuration (Important for Flutter Web/Android)
app.use(cors({
    origin: '*', // ✅ Allow all origins (replace with Flutter domain for security)
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true,
}));
app.options('*', cors()); // ✅ Handle preflight requests

// ✅ 5️⃣ Health Check Route
app.get('/', (req, res) => {
    res.json({ message: '🚀 Server is running on Railway!', status: 'healthy' });
});

// ✅ 6️⃣ Google Maps API Route
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

// ✅ 1️⃣0️⃣ 404 Handler
app.use((req, res) => {
    res.status(404).json({ error: '❌ Route not found' });
});

// ✅ 1️⃣1️⃣ Global Error Handler
app.use((err, req, res, next) => {
    logger.error(`❌ Error: ${err.message}`, { stack: err.stack });
    res.status(500).json({
        message: '❌ Internal server error',
        error: process.env.NODE_ENV === 'development' ? err.message : null,
    });
});

// ✅ 1️⃣2️⃣ Use Railway Provided PORT or Fallback
const PORT = process.env.PORT || 3000;

// ✅ 1️⃣3️⃣ Start the Server Gracefully
const server = app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
});

// ✅ Handle Port Already in Use Error Gracefully
server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
        console.error(`❌ Port ${PORT} is already in use. Shutting down...`);
        process.exit(1);
    } else {
        throw err;
    }
});

// ✅ 1️⃣4️⃣ Test Database Connection Before Fully Starting
(async () => {
    try {
        await pool.query('SELECT 1');
        console.log('✅ Database connected successfully!');
    } catch (error) {
        console.error('❌ Database connection error:', error.message);
        process.exit(1);
    }
})();

// ✅ 1️⃣5️⃣ Graceful Shutdown for Railway
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
