require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
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

// 🚫 Removed `/health` Route for Testing

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
const PORT = parseInt(process.env.PORT, 10) || 8080;

// ✅ Start Express Server
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on http://0.0.0.0:${PORT}`);
});



// ✅ Dummy Route to Force Long-Running Service
app.get('/hang', (req, res) => {
  console.log('💤 Hang route hit: Keeping Railway active');
  // Keeps the connection open indefinitely
  req.on('close', () => {
    console.log('❌ Hang route connection closed');
  });
});


// ✅ Start Keep-Alive
(async () => {
  keepAlive(); // ✅ Block event loop to keep Railway active
})();


// 🚫 Removed Self-Ping (`pingSelf()`) for Testing

// ✅ FINAL BLOCKER (Prevents Node.js from exiting)
async function keepAlive() {
  console.log('💓 Starting FINAL Railway Keep-Alive...');
  setInterval(() => {
    console.log('💓 Keep-alive heartbeat...');
  }, 10000); // Print heartbeat every 10 seconds

  await new Promise(() => {}); // BLOCKS FOREVER
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
