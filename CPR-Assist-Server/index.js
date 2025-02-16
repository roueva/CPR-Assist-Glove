require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const winston = require('winston');
const pool = require('./db');
const createAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed');


console.log("✅ Current Environment Variables:");
console.log(`POSTGRES_USER: ${process.env.POSTGRES_USER}`);
console.log(`POSTGRES_PASSWORD: ${process.env.POSTGRES_PASSWORD ? 'Set' : 'Not Set'}`);
console.log(`POSTGRES_HOST: ${process.env.POSTGRES_HOST}`);
console.log(`POSTGRES_DATABASE: ${process.env.POSTGRES_DATABASE}`);
console.log(`POSTGRES_PORT: ${process.env.POSTGRES_PORT}`);
console.log(`NODE_ENV: ${process.env.NODE_ENV}`);


// ✅ Winston Logger Setup
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

// ✅ `/health` Route for Railway Health Check
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({
      status: 'healthy',
      database: 'connected',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      database: 'error',
      error: error.message,
    });
  }
});

// ✅ Auth Routes (Pass `pool` directly)
app.use('/auth', createAuthRoutes(pool));

// ✅ Session Routes (Pass `pool` directly)
app.use('/sessions', createSessionRoutes(pool));

// ✅ AED Routes (Pass `pool` directly)
app.use('/aed', createAedRoutes(pool));

// ✅ 404 Handler
app.use((req, res) => {
  res.status(404).json({ error: '❌ Route not found' });
});

// ✅ Global Error Handler
app.use((err, req, res, next) => {
  logger.error(`❌ Error: ${err.message}`, { stack: err.stack });
  res.status(500).json({
    message: '❌ Internal server error',
    error: process.env.NODE_ENV === 'development' ? err.message : null,
  });
});

// ✅ Use Railway Port or Fallback
const PORT = process.env.PORT || 8080;

// ✅ Start Express Server
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

// ✅ Database Startup Check (Retries if Database Is Not Ready)
async function waitForDatabase(retries = 5, delay = 5000) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      await pool.query('SELECT 1');
      console.log('✅ Database is ready!');
      return;
    } catch (error) {
      console.warn(`⚠️ Database not ready (attempt ${attempt}/${retries}):`, error.message);
      if (attempt < retries) {
        await new Promise(res => setTimeout(res, delay));
      } else {
        console.error('❌ Database failed to connect after retries.');
        process.exit(1);
      }
    }
  }
}

// Catch Uncaught Exceptions (hard crashes)
process.on('uncaughtException', (error) => {
  console.error("❌ Uncaught Exception:", error);
  process.exit(1);
});

// Catch Unhandled Promise Rejections
process.on('unhandledRejection', (reason, promise) => {
  console.error("❌ Unhandled Rejection:", reason);
});


console.log('🚀 Loading Routes...');
app.use('/auth', createAuthRoutes(pool));
console.log('✅ Auth route loaded');
app.use('/sessions', createSessionRoutes(pool));
console.log('✅ Sessions route loaded');
app.use('/aed', createAedRoutes(pool));
console.log('✅ AED route loaded');
console.log('🚀 All routes loaded successfully');


// ✅ Railway Keep-Alive (Prevents Container Exit)
function keepAlive() {
  console.log('💓 Starting Railway Keep-Alive...');
  setInterval(() => {
    console.log('💓 Railway Keep-Alive Ping...');
  }, 1000 * 60 * 5); // Ping every 5 minutes

  // ✅ Proper Infinite Loop for Railway (Blocks Exit)
  setTimeout(() => {}, 1 << 30); // 2^30 milliseconds = blocks indefinitely
}

// ✅ Start Database Check and Keep-Alive
(async () => {
  await waitForDatabase(); // ✅ Wait for DB before proceeding
  keepAlive();             // ✅ Keep container alive for Railway
})();

// ✅ Graceful Shutdown Handler
process.on('SIGTERM', async () => {
  console.log('SIGTERM received, closing PostgreSQL pool...');
  await pool.end();
  console.log('✅ PostgreSQL pool closed. Exiting process.');
  process.exit(0);
});
process.on('SIGINT', async () => {
  console.log('SIGINT received, closing PostgreSQL pool...');
  await pool.end();
  console.log('✅ PostgreSQL pool closed. Exiting process.');
  process.exit(0);
});
