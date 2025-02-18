require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const winston = require('winston');
const { pool, ensureAedTable } = require('./db');
const initializeAuthRoutes = require('./routes/auth');
const createSessionRoutes = require('./routes/session');
const createAedRoutes = require('./routes/aed');

// ✅ Environment Configuration
const PORT = Number(process.env.PORT) || 8080;
const isProduction = process.env.NODE_ENV === 'production';


// ✅ Winston Logger Setup
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.printf(({ level, message }) => {
            if (level === 'error') {
                return `[${new Date().toISOString()}] ${message}`; // Only timestamp on errors
            }
            return `${message}`;
        })
    ),
    transports: [new winston.transports.Console()]
});



// ✅ Express Configuration
const app = express();
app.use(helmet());
app.use(express.json());
app.use(cors({
  origin: '*', // Accepts requests from everywhere (for development only)
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));


['DATABASE_URL', 'GOOGLE_MAPS_API_KEY'].forEach(key => {
    if (!process.env[key]) {
        logger.error(`🚨 Missing environment variable: ${key}`);
        process.exit(1);
    }
});


/// ✅ Improved Base Route (HTML or JSON)
app.get('/', (req, res) => {
    const uptime = process.uptime();
    const info = {
        status: 'Online',
        service: 'CPR Assist Backend',
        environment: process.env.NODE_ENV || 'development',
        database: process.env.DATABASE_URL ? 'Connected' : 'Not Set',
        version: '1.0.0',
        uptime: `${Math.floor(uptime / 60)} minutes, ${Math.floor(uptime % 60)} seconds`,
        timestamp: new Date().toISOString()
    };

    if (req.headers.accept && req.headers.accept.includes('text/html')) {
        // Show Pretty HTML if viewed in Browser
        res.send(`
      <html>
        <head>
          <title>CPR Assist Backend Status</title>
          <style>
            body { font-family: Arial, sans-serif; padding: 20px; background-color: #f0f8ff; }
            h1 { color: #2c3e50; }
            p { font-size: 16px; line-height: 1.5; }
            .info-box { border: 1px solid #2c3e50; padding: 15px; background-color: #dff9fb; border-radius: 5px; }
          </style>
        </head>
        <body>
          <h1>🚀 CPR Assist Backend Status</h1>
          <div class="info-box">
            <p><strong>Status:</strong> ${info.status}</p>
            <p><strong>Service:</strong> ${info.service}</p>
            <p><strong>Environment:</strong> ${info.environment}</p>
            <p><strong>Database:</strong> ${info.database}</p>
            <p><strong>Version:</strong> ${info.version}</p>
            <p><strong>Uptime:</strong> ${info.uptime}</p>
            <p><strong>Timestamp:</strong> ${info.timestamp}</p>
          </div>
        </body>
      </html>
    `);
    } else {
        // Return JSON if requested by API clients
        res.status(200).json(info);
    }
});

// ✅ Improved Health Check Route (HTML or JSON)
app.get('/health', async (req, res) => {
    const start = Date.now();
    try {
        await pool.query('SELECT 1');
        const duration = Date.now() - start;
        const healthInfo = {
            status: 'Healthy',
            database: 'Connected',
            responseTime: `${duration}ms`,
            environment: process.env.NODE_ENV || 'development',
            timestamp: new Date().toISOString()
        };

        if (req.headers.accept && req.headers.accept.includes('text/html')) {
            res.send(`
        <html>
          <head>
            <title>Health Check</title>
            <style>
              body { font-family: Arial, sans-serif; padding: 20px; background-color: #eafaf1; }
              h1 { color: #16a085; }
              .status-box { border: 1px solid #16a085; padding: 15px; background-color: #e8f5e9; border-radius: 5px; }
            </style>
          </head>
          <body>
            <h1>💚 Service Health Check</h1>
            <div class="status-box">
              <p><strong>Status:</strong> ${healthInfo.status}</p>
              <p><strong>Database:</strong> ${healthInfo.database}</p>
              <p><strong>Response Time:</strong> ${healthInfo.responseTime}</p>
              <p><strong>Environment:</strong> ${healthInfo.environment}</p>
              <p><strong>Timestamp:</strong> ${healthInfo.timestamp}</p>
            </div>
          </body>
        </html>
      `);
        } else {
            res.status(200).json(healthInfo);
        }
    } catch (error) {
        res.status(500).json({
            status: 'error',
            database: 'not connected',
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
});


// ✅ Initialize Routes
const initializeRoutes = () => {
    app.use('/auth', initializeAuthRoutes(pool));
    app.use('/sessions', createSessionRoutes(pool));
    app.use('/aed', createAedRoutes(pool)); 
};


initializeRoutes();



// ✅ Add this route to serve Google Maps API Key
app.get('/api/maps-key', (req, res) => {
  if (!process.env.GOOGLE_MAPS_API_KEY) {
    return res.status(500).json({ error: 'Google Maps API Key not set' });
  }
  res.json({ apiKey: process.env.GOOGLE_MAPS_API_KEY });
});


// ✅ Error Handlers
app.use('*', (req, res) => {
    logger.warn(`❌ Route Not Found: ${req.method} ${req.originalUrl}`);
    res.status(404).json({ error: `Route not found: ${req.originalUrl}` });
});

app.use((err, req, res, next) => {
    logger.error(`❌ Internal Server Error: ${err.message}`);
    res.status(500).json({
        message: 'Internal server error',
        error: isProduction ? null : err.message
    });
});


// ✅ Database Check
const checkDatabase = async () => {
    try {
        await pool.query('SELECT 1');
       // logger.info('✅ Database connection successful.');
        return true;
    } catch {
        throw new Error('❌ Database connection failed');
    }
};

process.on('unhandledRejection', (reason, promise) => {
    logger.error(`🚨 Unhandled Rejection: ${reason.stack || reason}`);
});

process.on('uncaughtException', (error) => {
    logger.error(`🚨 Uncaught Exception: ${error.message}`);
    process.exit(1);
});


// ✅ Server Startup
let server;
const startServer = async () => {
    try {
        await checkDatabase();
        await ensureAedTable();

        server = app.listen(PORT, '0.0.0.0', () => {
            logger.info(`🌐 Server running on http://0.0.0.0:${PORT} | Environment: ${process.env.NODE_ENV || 'development'}`);
        });
    } catch (error) {
        logger.error(`🚨 Server startup failed: ${error.message}`);
        process.exit(1);
    }
};

// ✅ Graceful Shutdown
const shutdown = async (signal) => {
    logger.info(`${signal} received...`);
    
    if (server) {
        server.close(() => {
            logger.info('HTTP server closed');
        });
    }
    
    try {
        await pool.end();
        logger.info('Database pool closed');
        process.exit(0);
    } catch (err) {
        logger.error('Error during shutdown:', err);
        process.exit(1);
    }
};

// ✅ Signal Handlers
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// ✅ Start Server
startServer();