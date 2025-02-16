const express = require('express');
const router = express.Router();

module.exports = (pool) => {
    // ✅ Fetch all AED locations
    router.get('/', async (req, res) => {
        try {
            const result = await pool.query("SELECT * FROM aed_locations;");
            res.json({ success: true, data: result.rows });
        } catch (error) {
            console.error("❌ Error fetching AED locations:", error);
            res.status(500).json({ success: false, message: "Failed to fetch AED locations." });
        }
    });

    // ✅ Insert or Update AED locations (Triggered by Python Script)
    router.post('/update', async (req, res) => {
        const { aeds } = req.body; // Expecting an array of AED objects
        if (!Array.isArray(aeds)) {
            return res.status(400).json({ success: false, message: "Invalid data format. Expected an array." });
        }

        const client = await pool.connect();
        try {
            for (const aed of aeds) {
                await client.query(`
                    INSERT INTO aed_locations (
                        id, latitude, longitude, name, address, emergency, 
                        operator, indoor, access, defibrillator_location, 
                        level, opening_hours, phone, wheelchair, last_updated
                    )
                    VALUES (
                        $1, $2, $3, $4, $5, $6, 
                        $7, $8, $9, $10, 
                        $11, $12, $13, $14, NOW()
                    )
                    ON CONFLICT (id) 
                    DO UPDATE SET 
                        latitude = EXCLUDED.latitude,
                        longitude = EXCLUDED.longitude,
                        name = EXCLUDED.name,
                        address = EXCLUDED.address,
                        emergency = EXCLUDED.emergency,
                        operator = EXCLUDED.operator,
                        indoor = EXCLUDED.indoor,
                        access = EXCLUDED.access,
                        defibrillator_location = EXCLUDED.defibrillator_location,
                        level = EXCLUDED.level,
                        opening_hours = EXCLUDED.opening_hours,
                        phone = EXCLUDED.phone,
                        wheelchair = EXCLUDED.wheelchair,
                        last_updated = NOW();
                `, [
                    aed.id, aed.latitude, aed.longitude, aed.name, 
                    aed.address, aed.emergency, aed.operator, 
                    aed.indoor, aed.access, aed.defibrillator_location, 
                    aed.level, aed.opening_hours, aed.phone, aed.wheelchair
                ]);
            }

            res.json({ success: true, message: "✅ AED locations updated successfully." });
        } catch (error) {
            console.error("❌ Error updating AED locations:", error);
            res.status(500).json({ success: false, message: "Failed to update AED locations." });
        } finally {
            client.release(); // ✅ Ensure the client is released
        }
    });

    return router; // ✅ Ensure the router is returned
};
