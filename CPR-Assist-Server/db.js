const { Pool } = require('pg');
require('dotenv').config(); // Load environment variables

console.log('Database connection details:', {
    user: process.env.POSTGRES_USER,
    host: process.env.POSTGRES_HOST,
    database: process.env.POSTGRES_DATABASE,
    port: process.env.POSTGRES_PORT,
});

// Create a new pool instance
//const pool = new Pool({     for local
  //  user: process.env.DB_USER,
  // host: process.env.DB_HOST,
  //  database: process.env.DB_DATABASE,
  //  password: process.env.DB_PASSWORD,
  //  port: process.env.POSTGRES_PORT || 5432,

// });


// Create a new pool instance with correct environment variables
const pool = new Pool({
    user: process.env.POSTGRES_USER,
    host: process.env.POSTGRES_HOST,
    database: process.env.POSTGRES_DATABASE,
    password: process.env.POSTGRES_PASSWORD,
    port: process.env.POSTGRES_PORT || 5432,
});

pool.on('error', (err) => {
    console.error('Unexpected error on idle client', err);
    process.exit(-1);
});

// Export the pool to use in other files
module.exports = pool;