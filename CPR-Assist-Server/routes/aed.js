const express = require('express');
const router = express.Router();
const AEDService = require('../services/aedService');

module.exports = (pool) => {
    // ✅ Fetch all AED locations
    router.get('/', async (req, res) => {
        try {
            const result = await pool.query("SELECT * FROM aed_locations ORDER BY name;");
            return res.json({ success: true, data: result.rows });
        } catch (error) {
            console.error("❌ Error fetching AED locations:", error);
            res.status(500).json({ success: false, message: "Failed to fetch AED locations." });
        }
    });

    // ✅ Get single AED by ID
    router.get('/:id', async (req, res) => {
        const { id } = req.params;
        
        try {
            const result = await pool.query("SELECT * FROM aed_locations WHERE id = $1", [id]);
            
            if (result.rows.length === 0) {
                return res.status(404).json({ success: false, message: "AED not found" });
            }
            
            return res.json({ success: true, data: result.rows[0] });
        } catch (error) {
            console.error("❌ Error fetching AED:", error);
            res.status(500).json({ success: false, message: "Failed to fetch AED." });
        }
    });

    // ✅ Sync AEDs from iSaveLives API
    router.post('/sync-isave-lives', async (req, res) => {
        const { deleteOld } = req.body;
        
        try {
            const aedService = new AEDService(pool);
            
            console.log('🔄 Starting iSaveLives AED sync...');
            const externalAEDs = await aedService.fetchFromExternalAPI();
            
            if (externalAEDs.length === 0) {
                return res.json({ 
                    success: true, 
                    message: 'No AEDs found in iSaveLives API',
                    inserted: 0,
                    updated: 0,
                    deleted: 0,
                    total: 0
                });
            }
            
            // Insert/update into database
            const result = await aedService.bulkInsertAEDs(externalAEDs);
            
            // Optionally delete old AEDs not in new data
            let deletedCount = 0;
            if (deleteOld === true) {
                const newAedIds = externalAEDs.map(aed => aed.id);
                deletedCount = await aedService.deleteOldAEDs(newAedIds);
            }
            
            res.json({ 
                success: true, 
                message: `✅ Successfully synced ${result.total} AEDs from iSaveLives`,
                inserted: result.inserted,
                updated: result.updated,
                deleted: deletedCount,
                total: result.total
            });
            
        } catch (error) {
            console.error('❌ Error syncing iSaveLives AEDs:', error);
            res.status(500).json({ 
                success: false, 
                message: 'Failed to sync iSaveLives AEDs',
                error: error.message
            });
        }
    });

    // ✅ Get AEDs near a location (within radius in kilometers)
    router.get('/near/:lat/:lng/:radius', async (req, res) => {
        const { lat, lng, radius } = req.params;
        const latitude = parseFloat(lat);
        const longitude = parseFloat(lng);
        const radiusKm = parseFloat(radius);

        if (isNaN(latitude) || isNaN(longitude) || isNaN(radiusKm)) {
            return res.status(400).json({ 
                success: false, 
                message: "Invalid coordinates or radius" 
            });
        }

        try {
            // Haversine formula to find nearby AEDs
            const result = await pool.query(`
                SELECT *,
                    (6371 * acos(
                        cos(radians($1)) * cos(radians(latitude)) * 
                        cos(radians(longitude) - radians($2)) + 
                        sin(radians($1)) * sin(radians(latitude))
                    )) AS distance
                FROM aed_locations
                WHERE (6371 * acos(
                    cos(radians($1)) * cos(radians(latitude)) * 
                    cos(radians(longitude) - radians($2)) + 
                    sin(radians($1)) * sin(radians(latitude))
                )) <= $3
                ORDER BY distance;
            `, [latitude, longitude, radiusKm]);

            return res.json({ 
                success: true, 
                count: result.rows.length,
                data: result.rows 
            });
        } catch (error) {
            console.error("❌ Error finding nearby AEDs:", error);
            res.status(500).json({ 
                success: false, 
                message: "Failed to find nearby AEDs." 
            });
        }
    });

    return router;
};