﻿require('dotenv').config(); // Load environment variables
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const winston = require('winston');
const pool = require('./db');
const createAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed');

// ✅ Winston Logger
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' }),
    new winston.transports.Console(),
  ],
});

// ✅ Express Configuration
const app = express();
app.use(helmet());
app.use(express.json());
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true,
}));
app.options('*', cors());

// ✅ 1️⃣ Health Check Route
app.get('/', (req, res) => {
  res.json({ message: '🚀 Server is running on Railway!', status: 'healthy' });
});

// ✅ 2️⃣ Google Maps API Key Route
app.get('/api/maps-key', (req, res) => {
  res.json({ apiKey: process.env.GOOGLE_MAPS_API_KEY });
});

// ✅ 3️⃣ Auth Routes
app.use('/auth', (req, res, next) => {
  req.db = pool;
  next();
}, createAuthRoutes(pool));

// ✅ 4️⃣ Session Routes
app.use('/sessions', (req, res, next) => {
  req.db = pool;
  next();
}, createSessionRoutes(pool));

// ✅ 5️⃣ AED Routes
app.use('/aed', createAedRoutes(pool));

// ✅ 6️⃣ 404 Handler
app.use((req, res) => {
  res.status(404).json({ error: '❌ Route not found' });
});

// ✅ 7️⃣ Global Error Handler
app.use((err, req, res, next) => {
  logger.error(`❌ Error: ${err.message}`, { stack: err.stack });
  res.status(500).json({
    message: '❌ Internal server error',
    error: process.env.NODE_ENV === 'development' ? err.message : null,
  });
});

// ✅ 8️⃣ Use Railway Port or Fallback
const PORT = process.env.PORT || 8080;

// ✅ 9️⃣ Start Express Server
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT}`);
});

// ✅ Handle Port Conflicts
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`❌ Port ${PORT} is already in use.`);
    process.exit(1);
  } else {
    throw err;
  }
});

// ✅ 1️⃣0️⃣ Railway Keep-Alive Mechanism (Best Practice)
// 🚨 Explanation: Create a blocking Promise to keep the event loop alive.
async function keepAlive() {
  console.log('💓 Starting Keep-Alive process for Railway');
  // Block the event loop with a long-running promise
  await new Promise(() => {
    setInterval(() => {
      console.log('💓 Keep-Alive Ping: Railway, I am still active');
    }, 1000 * 60 * 5); // Ping every 5 minutes
  });
}

// ✅ 1️⃣1️⃣ Start Keep-Alive Immediately (No Timeout)
keepAlive().catch(err => {
  console.error('❌ Keep-Alive Error:', err.message);
});

// ✅ 1️⃣2️⃣ Test Database Connection
(async () => {
  try {
    await pool.query('SELECT 1');
    console.log('✅ Database connected successfully!');
  } catch (error) {
    console.error('❌ Database connection error:', error.message);
    process.exit(1);
  }
})();

// ✅ 1️⃣3️⃣ Graceful Shutdown for Railway
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing pool...');
  await pool.end();
  console.log('✅ Pool closed. Exiting process.');
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT received, closing pool...');
  await pool.end();
  console.log('✅ Pool closed. Exiting process.');
  process.exit(0);
});
