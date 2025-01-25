const { Pool } = require('pg');
require('dotenv').config(); // Load environment variables

// Log database connection details for debugging (avoid logging sensitive data in production)
if (process.env.NODE_ENV !== 'production') {
    console.log('Database connection details:', {
        user: process.env.DB_USER || process.env.POSTGRES_USER,
        host: process.env.DB_HOST || process.env.POSTGRES_HOST,
        database: process.env.DB_DATABASE || process.env.POSTGRES_DATABASE,
        port: process.env.DB_PORT || process.env.POSTGRES_PORT || 5432,
    });
}

// Create a new pool instance based on the environment
const pool = new Pool({
    user: process.env.DB_USER || process.env.POSTGRES_USER,
    host: process.env.DB_HOST || process.env.POSTGRES_HOST,
    database: process.env.DB_DATABASE || process.env.POSTGRES_DATABASE,
    password: process.env.DB_PASSWORD || process.env.POSTGRES_PASSWORD,
    port: process.env.DB_PORT || process.env.POSTGRES_PORT || 5432,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, // Enable SSL in production
});

// Handle unexpected errors on the pool
pool.on('error', (err) => {
    console.error('Unexpected error on idle client:', err);
    process.exit(-1);
});

// Export the pool to use in other files
module.exports = pool;
