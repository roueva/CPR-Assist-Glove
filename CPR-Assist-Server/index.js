require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const winston = require('winston');
const pool = require('./db');
const initializeAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed');


// ✅ Environment Configuration
const PORT = Number(process.env.PORT) || 8080;
const HOST = '0.0.0.0';
const isProduction = process.env.NODE_ENV === 'production';

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
    new winston.transports.Console({
      format: winston.format.simple()
    })
  ]
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

// ✅ Improved Health Check Route
app.get('/health', async (req, res) => {
  try {
    // Test database connection
    await pool.query('SELECT 1');
    res.status(200).json({ 
      status: 'healthy',
      database: 'connected',
      environment: process.env.NODE_ENV,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Health check failed:', error);
    res.status(500).json({ 
      status: 'unhealthy',
      database: 'disconnected',
      error: isProduction ? 'Internal server error' : error.message
    });
  }
});

// ✅ Load Routes
const startRoutes = async () => {
  try {
    logger.info('🚀 Loading Routes...');
    
    app.use('/auth', initializeAuthRoutes(pool));
    logger.info('✅ Auth route loaded');
    
    app.use('/sessions', createSessionRoutes(pool));
    logger.info('✅ Sessions route loaded');
    
    app.use('/aed', createAedRoutes(pool));
    logger.info('✅ AED route loaded');
    
    logger.info('🚀 All routes loaded successfully');
  } catch (error) {
    logger.error('Failed to load routes:', error);
    throw error;
  }
};

// ✅ Error Handlers
app.use((req, res) => {
  res.status(404).json({ error: '❌ Route not found' });
});

app.use((err, req, res, next) => {
  logger.error('❌ Error:', err);
  res.status(500).json({
    message: '❌ Internal server error',
    error: isProduction ? null : err.message
  });
});

// ✅ Database Connection Check
const checkDatabaseConnection = async () => {
  try {
    await pool.query('SELECT 1');
    logger.info('✅ Database connection verified');
    return true;
  } catch (error) {
    logger.error('❌ Database connection failed:', error);
    return false;
  }
};

// ✅ Graceful Shutdown Handler
const gracefulShutdown = async (signal) => {
  logger.info(`${signal} received, starting graceful shutdown...`);
  
  try {
    logger.info('Closing PostgreSQL pool...');
    await pool.end();
    logger.info('✅ PostgreSQL pool closed');
    
    server.close(() => {
      logger.info('✅ Express server closed');
      process.exit(0);
    });

    // Force close after 10 seconds
    setTimeout(() => {
      logger.error('Could not close connections in time, forcefully shutting down');
      process.exit(1);
    }, 10000);
    
  } catch (error) {
    logger.error('Error during shutdown:', error);
    process.exit(1);
  }
};

// ✅ Start Server Function
const startServer = async () => {
  try {
    // Verify database connection first
    const dbConnected = await checkDatabaseConnection();
    if (!dbConnected) {
      throw new Error('Unable to connect to database');
    }

    // Load routes
    await startRoutes();

    // Start server
    const server = app.listen(PORT, HOST, () => {
      logger.info(`🚀 Server running on http://${HOST}:${PORT}`);
    });

        await new Promise(() => {}); // 🚀 Blocks event loop indefinitely


    // Event handlers
    server.on('error', (error) => {
      logger.error('Server error:', error);
      process.exit(1);
    });

    return server;

  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
};

// ✅ Process Event Handlers
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

process.on('uncaughtException', (err) => {
  logger.error('❌ Uncaught Exception:', err);
  gracefulShutdown('UNCAUGHT_EXCEPTION');
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('❌ Unhandled Rejection at:', promise, 'reason:', reason);
  gracefulShutdown('UNHANDLED_REJECTION');
});

// ✅ Start the server
startServer().catch((error) => {
  logger.error('Failed to start application:', error);
  process.exit(1);
});