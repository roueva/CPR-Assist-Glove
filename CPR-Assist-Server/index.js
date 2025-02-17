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
    allowedHeaders: ['Content-Type', 'Authorization']
}));

// ✅ Quick Health Check (Must be first route)
app.get('/health', async (req, res) => {
    try {
        await pool.query('SELECT 1');
        res.status(200).send('ok');
    } catch (error) {
        res.status(500).send('error');
    }
});

// ✅ Base Route
app.get('/', (req, res) => {
    res.status(200).json({
        status: 'online',
        environment: process.env.NODE_ENV
    });
});

// ✅ Initialize Routes
const initializeRoutes = () => {
    app.use('/auth', initializeAuthRoutes(pool));
    app.use('/sessions', createSessionRoutes(pool));
    app.use('/aed/locations', createAedRoutes(pool)); 
    logger.info('✅ All routes initialized');
};

// ✅ Error Handlers
app.use((req, res) => {
    res.status(404).json({ error: 'Route not found' });
});

app.use((err, req, res, next) => {
    logger.error('Error:', err);
    res.status(500).json({
        message: 'Internal server error',
        error: isProduction ? null : err.message
    });
});

// ✅ Database Check
const checkDatabase = async () => {
    try {
        await pool.query('SELECT 1');
        return true;
    } catch (error) {
        logger.error('Database connection failed:', error);
        return false;
    }
};

// ✅ Server Startup
let server;
const startServer = async () => {
    try {
        // Check database connection
        const dbConnected = await checkDatabase();
        if (!dbConnected) {
            throw new Error('Database connection failed');
        }

        // Ensure tables exist
        await ensureAedTable();
        
        // Initialize routes
        initializeRoutes();

        // Start server
        server = app.listen(PORT, HOST, () => {
            logger.info(`Server running on http://${HOST}:${PORT}`);
        });

        // Keep-alive ping
        setInterval(async () => {
            try {
                await pool.query('SELECT 1');
                logger.debug('Keep-alive ping successful');
            } catch (error) {
                logger.error('Keep-alive ping failed:', error);
            }
        }, 5000);

    } catch (error) {
        logger.error('Server startup failed:', error);
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