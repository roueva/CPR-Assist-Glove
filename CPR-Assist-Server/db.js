require('dotenv').config();
const { Pool } = require('pg');


const connectionString = process.env.DATABASE_URL;


// Pool Configuration
const pool = new Pool({
    connectionString,
    ssl: process.env.DATABASE_URL?.includes('railway.app') ? { rejectUnauthorized: false } : false,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    allowExitOnIdle: true,
});

// Pool Error Handling
pool.on('connect', () => {
    console.log('✅ PostgreSQL connected successfully');
});

pool.on('error', (err) => {
    console.error('❌ Unexpected PostgreSQL pool error:', err.message);
    if (err.code === 'ECONNREFUSED') {
        console.error('💀 Database connection refused — is PostgreSQL running?');
    } else if (err.code === '57P01') {
        console.error('🔌 Database connection terminated by admin.');
    } else if (err.code === '53300') {
        console.error('🔒 Too many database connections — consider reducing pool size.');
    } else if (err.code === '08006' || err.code === '08001') {
        console.error('📡 Database connection failure.');
    }
});

// Table Creation
async function ensureAedTable() {
    let client;
    try {
        client = await pool.connect();

        await client.query(`
            CREATE TABLE IF NOT EXISTS aed_locations (
                id BIGINT PRIMARY KEY,
                foundation TEXT,
                address TEXT,
                latitude DOUBLE PRECISION NOT NULL,
                longitude DOUBLE PRECISION NOT NULL,
                availability TEXT,
                aed_webpage TEXT,
                last_updated TIMESTAMP DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS aed_sync_log (
                id SERIAL PRIMARY KEY,
                synced_at TIMESTAMP DEFAULT NOW(),
                aeds_checked INTEGER,
                aeds_inserted INTEGER,
                aeds_updated INTEGER
            );
        `);

        await client.query(`
    CREATE TABLE IF NOT EXISTS availability_cache (
        id SERIAL PRIMARY KEY,
        availability_text TEXT UNIQUE NOT NULL,
        parsed_data JSONB NOT NULL,
        parsed_at TIMESTAMP DEFAULT NOW()
    );
`);

        await client.query(`
    CREATE INDEX IF NOT EXISTS idx_availability_text 
    ON availability_cache (availability_text);
`);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_aed_lat_lng 
            ON aed_locations (latitude, longitude);
        `);

        return true;
    } catch (err) {
        console.error("❌ Error ensuring AED table:", err);
        return false;
    } finally {
        if (client) {
            client.release();
        }
    }
}

async function ensureSessionTables() {
    let client;
    try {
        client = await pool.connect();

        // ── New columns on cpr_sessions ──────────────────────────────────────
        const newColumns = [
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS mode VARCHAR(25) DEFAULT 'emergency'`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS average_force FLOAT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS peak_depth FLOAT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS average_effective_depth FLOAT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS over_force_count INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS too_deep_count INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS leaning_count INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS correct_posture INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS ventilation_count INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS ventilation_compliance FLOAT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS pulse_checks_prompted INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS pulse_checks_complied INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS pulse_detected_final BOOLEAN DEFAULT false`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS fatigue_onset_index INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS rate_variability FLOAT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS consecutive_good_peak INT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS time_to_first_comp FLOAT DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS patient_temperature FLOAT`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS synced_from_local BOOLEAN DEFAULT false`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS note VARCHAR(500)`,
        ];

        for (const sql of newColumns) {
            await client.query(sql);
        }

        // ── session_compressions ─────────────────────────────────────────────
        await client.query(`
            CREATE TABLE IF NOT EXISTS session_compressions (
                id                    BIGSERIAL PRIMARY KEY,
                session_id            BIGINT NOT NULL REFERENCES cpr_sessions(id) ON DELETE CASCADE,
                timestamp_ms          INT NOT NULL,
                depth                 FLOAT NOT NULL,
                frequency             FLOAT NOT NULL,
                force                 FLOAT DEFAULT 0,
                recoil_achieved       BOOLEAN DEFAULT false,
                over_force            BOOLEAN DEFAULT false,
                posture_ok            BOOLEAN DEFAULT false,
                leaning_detected      BOOLEAN DEFAULT false,
                wrist_alignment_angle FLOAT DEFAULT 0,
                effective_depth       FLOAT DEFAULT 0
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_compressions_session_id
            ON session_compressions (session_id, timestamp_ms);
        `);

        // ── session_ventilations ─────────────────────────────────────────────
        await client.query(`
            CREATE TABLE IF NOT EXISTS session_ventilations (
                id                  BIGSERIAL PRIMARY KEY,
                session_id          BIGINT NOT NULL REFERENCES cpr_sessions(id) ON DELETE CASCADE,
                timestamp_ms        INT NOT NULL,
                cycle_number        INT NOT NULL,
                ventilations_given  INT DEFAULT 0,
                duration_sec        FLOAT DEFAULT 0,
                compliant           BOOLEAN DEFAULT false
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_ventilations_session_id
            ON session_ventilations (session_id, timestamp_ms);
        `);

        // ── session_pulse_checks ─────────────────────────────────────────────
        await client.query(`
            CREATE TABLE IF NOT EXISTS session_pulse_checks (
                id               BIGSERIAL PRIMARY KEY,
                session_id       BIGINT NOT NULL REFERENCES cpr_sessions(id) ON DELETE CASCADE,
                timestamp_ms     INT NOT NULL,
                interval_number  INT NOT NULL,
                detected         BOOLEAN DEFAULT false,
                detected_bpm     FLOAT DEFAULT 0,
                confidence       INT DEFAULT 0,
                perfusion_index  INT DEFAULT 0,
                user_decision    VARCHAR(20)
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_pulse_checks_session_id
            ON session_pulse_checks (session_id, timestamp_ms);
        `);

        // ── session_rescuer_vitals ───────────────────────────────────────────
        await client.query(`
            CREATE TABLE IF NOT EXISTS session_rescuer_vitals (
                id             BIGSERIAL PRIMARY KEY,
                session_id     BIGINT NOT NULL REFERENCES cpr_sessions(id) ON DELETE CASCADE,
                timestamp_ms   INT NOT NULL,
                heart_rate     FLOAT DEFAULT 0,
                spo2           FLOAT DEFAULT 0,
                temperature    FLOAT DEFAULT 0,
                signal_quality INT DEFAULT 0,
                pause_type     VARCHAR(20)
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_rescuer_vitals_session_id
            ON session_rescuer_vitals (session_id, timestamp_ms);
        `);

        return true;
    } catch (err) {
        console.error('❌ Error ensuring session tables:', err);
        return false;
    } finally {
        if (client) client.release();
    }
}

// ✅ Export both pool and initialization function
module.exports = { pool, ensureAedTable, ensureSessionTables };
