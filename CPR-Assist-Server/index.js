require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const fetch = require('node-fetch'); // ✅ Add fetch for self-ping
const winston = require('winston');
const pool = require('./db');
const createAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed');

// ✅ Log Environment Variables
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

// ✅ Auth Routes
console.log('🚀 Loading Routes...');
app.use('/auth', createAuthRoutes(pool));
console.log('✅ Auth route loaded');
app.use('/sessions', createSessionRoutes(pool));
console.log('✅ Sessions route loaded');
app.use('/aed', createAedRoutes(pool));
console.log('✅ AED route loaded');
console.log('🚀 All routes loaded successfully');

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
  pingSelf(); // ✅ Start Self-Ping to Prevent Auto-Sleep
});

// ✅ Self-Ping Task to Keep Railway Active
// ✅ Self-Ping Task to Keep Railway Active
async function pingSelf() {
  const url = `http://127.0.0.1:${PORT}/health`; // ✅ Use IPv4 to Fix ECONNREFUSED
  setInterval(async () => {
    try {
      const response = await fetch(url);
      if (response.ok) {
        console.log(`💓 Self-ping successful to ${url}`);
      } else {
        console.warn(`⚠️ Self-ping failed: ${response.status}`);
      }
    } catch (error) {
      console.error(`❌ Error during self-ping: ${error.message}`);
    }
  }, 10000); // Ping every 10 seconds
}

// ✅ FINAL AND CORRECT KEEP-ALIVE (BLOCKS NODE.JS FOREVER)
async function keepAlive() {
  console.log('💓 Starting FINAL Railway Keep-Alive...');
  await new Promise(() => {}); // ✅ BLOCKS EVENT LOOP FOREVER
}

// ✅ Start Database Check and Keep-Alive
(async () => {
  keepAlive(); // ✅ Keep container alive for Railway
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
