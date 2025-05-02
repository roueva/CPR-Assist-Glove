const express = require('express');
const router = express.Router();
const axios = require('axios');
const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY;


module.exports = (pool) => {
    // ✅ Fetch all AED locations
    router.get('/', async (req, res) => {
        try {
            const result = await pool.query("SELECT * FROM aed_locations;");

            if (result.rows.length === 0) {
                return res.json({ success: true, message: "No AED locations found.", data: [] });
            }

            res.json({ success: true, data: result.rows });
        } catch (error) {
            console.error("❌ Error fetching AED locations:", error);
            res.status(500).json({ success: false, message: "Failed to fetch AED locations." });
        }
    });

    // ✅ Bulk Insert/Update AED locations (for Python script or admin sync)
    router.post('/bulk-update', async (req, res) => {
        const { aeds } = req.body;

        if (!Array.isArray(aeds)) {
            return res.status(400).json({ success: false, message: "Invalid data format. Expected 'aeds' array." });
        }

        const client = await pool.connect();
        try {
            for (const aed of aeds) {
                // If address is missing or unknown, geocode it
                let address = aed.address?.trim() || '';
                if (!address || address.toLowerCase().includes('unknown') || address.length < 5) {
                    address = await geocodeLatLng(aed.latitude, aed.longitude, GOOGLE_MAPS_API_KEY);
                }

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
                    aed.id,
                    aed.latitude,
                    aed.longitude,
                    aed.name || '',
                    address,
                    aed.emergency || '',
                    aed.operator || '',
                    !!aed.indoor,
                    aed.access || '',
                    aed.defibrillator_location || '',
                    aed.level || '',
                    aed.opening_hours || '',
                    aed.phone || '',
                    !!aed.wheelchair
                ]
               );
            }

            res.json({ success: true, message: "✅ AED locations bulk updated." });
        } catch (error) {
            console.error("❌ Error in bulk AED update:", error);
            res.status(500).json({ success: false, message: "Bulk update failed." });
        } finally {
            client.release();
        }
    });

    async function geocodeLatLng(lat, lng, apiKey) {
        const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${apiKey}`;

        try {
            const res = await axios.get(url);
            if (res.data.status === 'OK') {
                const result = res.data.results[0];
                const components = result.address_components;
                let route = '', streetNumber = '';

                for (const c of components) {
                    if (c.types.includes('route')) route = c.long_name;
                    if (c.types.includes('street_number')) streetNumber = c.long_name;
                }

                return route && streetNumber ? `${route} ${streetNumber}` : result.formatted_address;
            } else {
                return null;
            }
        } catch (err) {
            console.error("❌ Geocoding failed:", err.message);
            return null;
        }
    }


    // ✅ Lightweight update for frontend geocoded address sync
    router.post('/locations/update', async (req, res) => {
        const { aed_list } = req.body;

        if (!Array.isArray(aed_list)) {
            return res.status(400).json({ message: 'aed_list is required and must be an array' });
        }

        try {
            for (const aed of aed_list) {
                const { id, address, latitude, longitude } = aed;

                await pool.query(`
          UPDATE aed_locations
          SET
            address = $1,
            latitude = $2,
            longitude = $3,
            last_updated = NOW()
          WHERE id = $4
        `, [address, latitude, longitude, id]);
            }

            res.json({ status: 'success', updated: aed_list.length });
        } catch (err) {
            console.error("❌ Error updating AED addresses:", err);
            res.status(500).json({ message: 'Server error while updating AEDs' });
        }
    });

    return router;
};
