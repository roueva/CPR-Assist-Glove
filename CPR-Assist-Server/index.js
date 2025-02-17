require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const winston = require('winston');
const pool = require('./db');
const createAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed');

// ✅ Parse PORT Correctly (Fix Railway quotes issue)
const PORT = Number(process.env.PORT) || 8080;
const HOST = '0.0.0.0';
console.log(`🚀 Using PORT: ${PORT} (Type: ${typeof PORT})`);

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

// ✅ Health Check Route (for Railway)
app.get('/health', (req, res) => {
  res.status(200).json({ message: '✅ Health OK', status: 'healthy' });
});

// ✅ Load Routes
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

// ✅ Start Express Server
const server = app.listen(PORT, HOST, () => {
  console.log(`🚀 Server running on http://${HOST}:${PORT}`);
});

// ✅ Keep Event Loop Active (Prevents Railway Stop)
setInterval(() => {
  console.log('💓 Railway Keep-Alive Ping');
}, 10000); // Every 10 seconds

// ✅ Prevent Node.js from Exiting (Railway fix)
process.stdin.resume();

// ✅ Graceful Shutdown Handling
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

// ✅ Global Crash Handlers (Very Important)
process.on('uncaughtException', (err) => {
  console.error('❌ Uncaught Exception:', err);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('❌ Unhandled Rejection:', promise, 'reason:', reason);
  process.exit(1);
});
