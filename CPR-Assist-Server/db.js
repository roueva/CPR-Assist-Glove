require('dotenv').config();
const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
    console.warn('⚠️ DATABASE_URL is not set.');
}

// ── Pool Configuration ────────────────────────────────────────────────────────

const pool = new Pool({
    connectionString,
    ssl: connectionString?.includes('railway.app')
        ? { rejectUnauthorized: false }
        : false,
    max: 20,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    allowExitOnIdle: true,
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

// ── AED Tables ────────────────────────────────────────────────────────────────

async function ensureAedTable() {
    let client;

    try {
        client = await pool.connect();
        await client.query('BEGIN');

        await client.query(`
            CREATE TABLE IF NOT EXISTS aed_locations (
                id           BIGINT PRIMARY KEY,
                foundation   TEXT,
                address      TEXT,
                latitude     DOUBLE PRECISION NOT NULL,
                longitude    DOUBLE PRECISION NOT NULL,
                availability TEXT,
                aed_webpage  TEXT,
                last_updated TIMESTAMP DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS aed_sync_log (
                id           SERIAL PRIMARY KEY,
                synced_at    TIMESTAMP DEFAULT NOW(),
                aeds_checked INTEGER,
                aeds_inserted INTEGER,
                aeds_updated INTEGER
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS availability_cache (
                id                SERIAL PRIMARY KEY,
                availability_text TEXT UNIQUE NOT NULL,
                parsed_data       JSONB NOT NULL,
                parsed_at         TIMESTAMP DEFAULT NOW()
            );
        `);

        // UNIQUE on availability_text already creates an index — no separate one needed.
        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_aed_lat_lng
            ON aed_locations (latitude, longitude);
        `);

        await client.query('COMMIT');
        return true;
    } catch (err) {
        if (client) {
            try { await client.query('ROLLBACK'); } catch (_) { }
        }
        console.error('❌ Error ensuring AED tables:', err);
        return false;
    } finally {
        if (client) client.release();
    }
}

// ── Session Tables ────────────────────────────────────────────────────────────

async function ensureSessionTables() {
    let client;

    try {
        client = await pool.connect();
        await client.query('BEGIN');

        // ── cpr_sessions — base table ────────────────────────────────────────
        // Full schema for fresh installs.
        // The migrations block below handles older deployments safely.
        await client.query(`
            CREATE TABLE IF NOT EXISTS cpr_sessions (
                id                      BIGSERIAL PRIMARY KEY,
                user_id                 BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                mode                    VARCHAR(25)  DEFAULT 'emergency',
                scenario                VARCHAR(40)  DEFAULT 'standard_adult',
                session_start           TIMESTAMP    NOT NULL,
                session_end             TIMESTAMP,
                compression_count       INT          DEFAULT 0,
                correct_depth           INT          DEFAULT 0,
                correct_frequency       INT          DEFAULT 0,
                correct_recoil          INT          DEFAULT 0,
                depth_rate_combo        INT          DEFAULT 0,
                correct_posture         INT          DEFAULT 0,
                leaning_count           INT          DEFAULT 0,
                over_force_count        INT          DEFAULT 0,
                too_deep_count          INT          DEFAULT 0,
                correct_ventilations    INT          DEFAULT 0,
                average_depth           FLOAT        DEFAULT 0,
                average_frequency       FLOAT        DEFAULT 0,
                average_effective_depth FLOAT        DEFAULT 0,
                peak_depth              FLOAT        DEFAULT 0,
                depth_sd                FLOAT        DEFAULT 0,
                depth_consistency       FLOAT        DEFAULT 0,
                freq_consistency        FLOAT        DEFAULT 0,
                hands_on_ratio          FLOAT        DEFAULT 1,
                no_flow_time            FLOAT        DEFAULT 0,
                no_flow_intervals       INT          DEFAULT 0,
                rate_variability        FLOAT        DEFAULT 0,
                time_to_first_comp      FLOAT        DEFAULT 0,
                consecutive_good_peak   INT          DEFAULT 0,
                fatigue_onset_index     INT          DEFAULT 0,
                rescuer_swap_count      INT          DEFAULT 0,
                ventilation_count       INT          DEFAULT 0,
                ventilation_compliance  FLOAT        DEFAULT 0,
                pulse_checks_prompted   INT          DEFAULT 0,
                pulse_checks_complied   INT          DEFAULT 0,
                pulse_detected_final    BOOLEAN      DEFAULT false,
                patient_temperature     FLOAT,
                rescuer_hr_last_pause   FLOAT,
                rescuer_spo2_last_pause FLOAT,
                ambient_temp_start      FLOAT,
                ambient_temp_end        FLOAT,
                user_heart_rate         FLOAT,
                user_temperature        FLOAT,
                session_duration        INT          DEFAULT 0,
                total_grade             FLOAT        DEFAULT 0,
                synced_from_local       BOOLEAN      DEFAULT false,
                note                    VARCHAR(500)
            );
        `);

        // ── session_compressions ─────────────────────────────────────────────
        await client.query(`
            CREATE TABLE IF NOT EXISTS session_compressions (
                id                    BIGSERIAL PRIMARY KEY,
                session_id            BIGINT  NOT NULL REFERENCES cpr_sessions(id) ON DELETE CASCADE,
                timestamp_ms          INT     NOT NULL,
                depth                 FLOAT   NOT NULL,
                frequency             FLOAT   NOT NULL,
                instantaneous_rate    FLOAT   DEFAULT 0,
                force                 FLOAT   DEFAULT 0,
                recoil_achieved       BOOLEAN DEFAULT false,
                over_force            BOOLEAN DEFAULT false,
                posture_ok            BOOLEAN DEFAULT false,
                leaning_detected      BOOLEAN DEFAULT false,
                wrist_alignment_angle FLOAT   DEFAULT 0,
                wrist_flexion_angle   FLOAT   DEFAULT 0,
                compression_axis_dev  FLOAT   DEFAULT 0,
                effective_depth       FLOAT   DEFAULT 0,
                peak_force            FLOAT   DEFAULT 0,
                downstroke_time_ms    INT     DEFAULT 0
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_compressions_session_id
            ON session_compressions (session_id, timestamp_ms);
        `);

        // ── session_ventilations ─────────────────────────────────────────────
        await client.query(`
            CREATE TABLE IF NOT EXISTS session_ventilations (
                id                 BIGSERIAL PRIMARY KEY,
                session_id         BIGINT  NOT NULL REFERENCES cpr_sessions(id) ON DELETE CASCADE,
                timestamp_ms       INT     NOT NULL,
                cycle_number       INT     NOT NULL,
                ventilations_given INT     DEFAULT 0,
                duration_sec       FLOAT   DEFAULT 0,
                compliant          BOOLEAN DEFAULT false
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
                session_id       BIGINT  NOT NULL REFERENCES cpr_sessions(id) ON DELETE CASCADE,
                timestamp_ms     INT     NOT NULL,
                interval_number  INT     NOT NULL,
                classification   INT     DEFAULT 0,
                detected         BOOLEAN DEFAULT false,
                detected_bpm     FLOAT   DEFAULT 0,
                confidence       INT     DEFAULT 0,
                perfusion_index  INT     DEFAULT 0,
                detector_a_count INT     DEFAULT 0,
                detector_b_count INT     DEFAULT 0,
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
                session_id     BIGINT  NOT NULL REFERENCES cpr_sessions(id) ON DELETE CASCADE,
                timestamp_ms   INT     NOT NULL,
                heart_rate     FLOAT   DEFAULT 0,
                spo2           FLOAT   DEFAULT 0,
                rmssd          FLOAT   DEFAULT 0,
                rescuer_pi     INT     DEFAULT 0,
                temperature    FLOAT   DEFAULT 0,
                fatigue_score  INT     DEFAULT 0,
                signal_quality INT     DEFAULT 0,
                pause_type     VARCHAR(20)
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_rescuer_vitals_session_id
            ON session_rescuer_vitals (session_id, timestamp_ms);
        `);

        // ── Migrations for older deployments ─────────────────────────────────
        // Safe to run on every startup — ADD COLUMN IF NOT EXISTS is a no-op
        // when the column already exists. Keeps older Railway instances in sync.
        const migrations = [
            // cpr_sessions — columns that may be absent on old instances
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS mode                    VARCHAR(25)  DEFAULT 'emergency'`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS scenario                VARCHAR(40)  DEFAULT 'standard_adult'`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS peak_depth              FLOAT        DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS average_effective_depth FLOAT        DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS over_force_count        INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS too_deep_count          INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS leaning_count           INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS correct_posture         INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS correct_ventilations    INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS ventilation_count       INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS ventilation_compliance  FLOAT        DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS pulse_checks_prompted   INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS pulse_checks_complied   INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS pulse_detected_final    BOOLEAN      DEFAULT false`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS fatigue_onset_index     INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS rate_variability        FLOAT        DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS consecutive_good_peak   INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS time_to_first_comp      FLOAT        DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS patient_temperature     FLOAT`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS rescuer_hr_last_pause   FLOAT`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS rescuer_spo2_last_pause FLOAT`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS synced_from_local       BOOLEAN      DEFAULT false`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS note                    VARCHAR(500)`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS depth_sd               FLOAT        DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS no_flow_intervals       INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS rescuer_swap_count      INT          DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS ambient_temp_start      FLOAT`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS ambient_temp_end        FLOAT`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS hands_on_ratio          FLOAT        DEFAULT 1`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS no_flow_time            FLOAT        DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS depth_consistency       FLOAT        DEFAULT 0`,
            `ALTER TABLE cpr_sessions ADD COLUMN IF NOT EXISTS freq_consistency        FLOAT        DEFAULT 0`,

            // Add FK from cpr_sessions.user_id → users.id with cascade delete
            // DO $$ wrapping makes it safe to re-run — it only adds the constraint if it doesn't already exist
            `DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'cpr_sessions_user_id_fkey'
      AND table_name = 'cpr_sessions'
  ) THEN
    ALTER TABLE cpr_sessions
      ADD CONSTRAINT cpr_sessions_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;
  END IF;
END $$`,

            // Type fix — safe cast via text to handle any legacy non-numeric values
            `ALTER TABLE cpr_sessions ALTER COLUMN user_heart_rate TYPE FLOAT USING NULLIF(user_heart_rate::text, '')::float`,

            // Remove obsolete column (average_force was internal metric, never displayed)
            `ALTER TABLE cpr_sessions DROP COLUMN IF EXISTS average_force`,

            // session_compressions — columns added in v3.0
            `ALTER TABLE session_compressions ADD COLUMN IF NOT EXISTS instantaneous_rate   FLOAT DEFAULT 0`,
            `ALTER TABLE session_compressions ADD COLUMN IF NOT EXISTS wrist_flexion_angle  FLOAT DEFAULT 0`,
            `ALTER TABLE session_compressions ADD COLUMN IF NOT EXISTS compression_axis_dev FLOAT DEFAULT 0`,
            `ALTER TABLE session_compressions ADD COLUMN IF NOT EXISTS peak_force           FLOAT DEFAULT 0`,
            `ALTER TABLE session_compressions ADD COLUMN IF NOT EXISTS downstroke_time_ms   INT   DEFAULT 0`,

            // session_pulse_checks — columns added in v3.0
            `ALTER TABLE session_pulse_checks ADD COLUMN IF NOT EXISTS classification   INT DEFAULT 0`,
            `ALTER TABLE session_pulse_checks ADD COLUMN IF NOT EXISTS detector_a_count INT DEFAULT 0`,
            `ALTER TABLE session_pulse_checks ADD COLUMN IF NOT EXISTS detector_b_count INT DEFAULT 0`,

            // session_rescuer_vitals — columns added in v3.0
            `ALTER TABLE session_rescuer_vitals ADD COLUMN IF NOT EXISTS rmssd         FLOAT DEFAULT 0`,
            `ALTER TABLE session_rescuer_vitals ADD COLUMN IF NOT EXISTS rescuer_pi    INT   DEFAULT 0`,
            `ALTER TABLE session_rescuer_vitals ADD COLUMN IF NOT EXISTS fatigue_score INT   DEFAULT 0`,
        ];

        for (const sql of migrations) {
            await client.query(sql);
        }

        await client.query('COMMIT');
        return true;
    } catch (err) {
        if (client) {
            try { await client.query('ROLLBACK'); } catch (_) { }
        }
        console.error('❌ Error ensuring session tables:', err);
        return false;
    } finally {
        if (client) client.release();
    }
}

// ── One-shot startup initializer ──────────────────────────────────────────────

async function initializeDatabase() {
    let client;

    try {
        client = await pool.connect();
        await client.query('SELECT 1');
        client.release();
        client = null;

        console.log('✅ PostgreSQL connection verified');

        const aedOk = await ensureAedTable();
        const sessionOk = await ensureSessionTables();

        if (!aedOk || !sessionOk) {
            throw new Error('Database schema initialization failed');
        }

        console.log('✅ PostgreSQL schema ensured successfully');
        return true;
    } catch (err) {
        if (client) client.release();
        console.error('❌ Database initialization error:', err.message);
        return false;
    }
}

module.exports = {
    pool,
    ensureAedTable,
    ensureSessionTables,
    initializeDatabase,
};