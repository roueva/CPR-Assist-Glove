const express = require('express');
const { authenticate } = require('../middleware/validation');

module.exports = function (pool) {
    const router = express.Router();

    // ── GET /leaderboard/global ─────────────────────────────────────────────
    // Top 50 users ranked by average total_grade (min 3 sessions to qualify).
    // Returns rank, username, avg_grade, session_count.
    // No sensitive data — username only, no email/id exposed.

    router.get('/global', authenticate, async (req, res) => {
        try {
            const result = await pool.query(
                `SELECT
           u.username,
           COUNT(s.id)::int                           AS session_count,
           ROUND(AVG(s.total_grade)::numeric, 1)       AS avg_grade,
           ROUND(MAX(s.total_grade)::numeric, 1)        AS best_grade
         FROM cpr_sessions s
         JOIN users u ON u.id = s.user_id
         GROUP BY u.id, u.username
         HAVING COUNT(s.id) >= 3
         ORDER BY avg_grade DESC
         LIMIT 50`
            );

            // Inject rank and flag current user's row
            const userId = req.user.id;
            const currentUserResult = await pool.query(
                'SELECT username FROM users WHERE id = $1', [userId]
            );
            const currentUsername = currentUserResult.rows[0]?.username;

            const ranked = result.rows.map((row, index) => ({
                rank: index + 1,
                username: row.username,
                session_count: row.session_count,
                avg_grade: parseFloat(row.avg_grade),
                best_grade: parseFloat(row.best_grade),
                is_current_user: row.username === currentUsername,
            }));

            // Find current user's position even if outside top 50
            let myRank = ranked.find(r => r.is_current_user);

            if (!myRank) {
                const myStatsResult = await pool.query(
                    `SELECT
             COUNT(s.id)::int                         AS session_count,
             ROUND(AVG(s.total_grade)::numeric, 1)     AS avg_grade,
             (
               SELECT COUNT(DISTINCT u2.id) + 1
               FROM cpr_sessions s2
               JOIN users u2 ON u2.id = s2.user_id
               GROUP BY u2.id
               HAVING AVG(s2.total_grade) > AVG(s.total_grade)
             ) AS rank
           FROM cpr_sessions s
           WHERE s.user_id = $1`,
                    [userId]
                );

                const myRow = myStatsResult.rows[0];
                if (myRow && myRow.session_count >= 3) {
                    myRank = {
                        rank: myRow.rank ?? 99,
                        username: currentUsername,
                        session_count: myRow.session_count,
                        avg_grade: parseFloat(myRow.avg_grade),
                        is_current_user: true,
                    };
                }
            }

            res.json({ success: true, data: ranked, my_rank: myRank ?? null });
        } catch (err) {
            console.error('Error fetching global leaderboard:', err.message);
            res.status(500).json({ success: false, message: 'Failed to fetch leaderboard.' });
        }
    });

    // ── GET /leaderboard/global/rank — current user's rank only ────────────
    // Lightweight call for the drawer footer. Returns just rank + stats.

    router.get('/global/rank', authenticate, async (req, res) => {
        const userId = req.user.id;
        try {
            const result = await pool.query(
                `WITH user_avgs AS (
           SELECT
             user_id,
             AVG(total_grade) AS avg_grade,
             COUNT(*)         AS session_count
           FROM cpr_sessions
           GROUP BY user_id
           HAVING COUNT(*) >= 3
         ),
         ranked AS (
           SELECT
             user_id,
             avg_grade,
             session_count,
             RANK() OVER (ORDER BY avg_grade DESC) AS rank
           FROM user_avgs
         )
         SELECT rank, avg_grade, session_count
         FROM ranked
         WHERE user_id = $1`,
                [userId]
            );

            if (result.rows.length === 0) {
                // User hasn't qualified yet (< 3 sessions)
                const countResult = await pool.query(
                    'SELECT COUNT(*)::int AS n FROM cpr_sessions WHERE user_id = $1',
                    [userId]
                );
                return res.json({
                    success: true,
                    data: {
                        rank: null,
                        avg_grade: null,
                        session_count: countResult.rows[0].n,
                        qualified: false,
                        sessions_until_rank: Math.max(0, 3 - countResult.rows[0].n),
                    },
                });
            }

            const row = result.rows[0];
            res.json({
                success: true,
                data: {
                    rank: parseInt(row.rank),
                    avg_grade: parseFloat(row.avg_grade).toFixed(1),
                    session_count: row.session_count,
                    qualified: true,
                },
            });
        } catch (err) {
            console.error('Error fetching user rank:', err.message);
            res.status(500).json({ success: false, message: 'Failed to fetch rank.' });
        }
    });

    return router;
};