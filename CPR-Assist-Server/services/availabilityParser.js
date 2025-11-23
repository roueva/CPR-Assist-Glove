const { spawn } = require('child_process');
const fs = require('fs').promises;
const path = require('path');

class AvailabilityParser {
    constructor() {
        this.scriptPath = path.join(__dirname, '../scripts/parse_aed_data.py');
        this.cacheFile = path.join(__dirname, '../data/parsed_availability_map.json');
        this.inputFile = path.join(__dirname, '../data/aed_greece_current.json');
    }

    async extractAvailabilityStrings(aeds) {
        const uniqueStrings = new Set();
        
        for (const aed of aeds) {
            if (aed.availability && aed.availability.trim()) {
                uniqueStrings.add(aed.availability.trim());
            }
        }
        
        return Array.from(uniqueStrings);
    }

    async loadCache() {
        try {
            const data = await fs.readFile(this.cacheFile, 'utf8');
            return JSON.parse(data);
        } catch (error) {
            console.log('⚠️ No existing cache found, starting fresh');
            return {};
        }
    }

    async getUnparsedStrings(aeds) {
        const currentStrings = await this.extractAvailabilityStrings(aeds);
        const cache = await this.loadCache();
        
        const unparsed = currentStrings.filter(str => !cache[str]);
        
        console.log(`📊 Availability Analysis:`);
        console.log(`   → Total unique strings: ${currentStrings.length}`);
        console.log(`   → Already cached: ${currentStrings.length - unparsed.length}`);
        console.log(`   → Need parsing: ${unparsed.length}`);
        
        return unparsed;
    }

    async saveAEDsToFile(aeds) {
        const dataDir = path.dirname(this.inputFile);
        try {
            await fs.mkdir(dataDir, { recursive: true });
        } catch (error) {
            // Directory might already exist
        }

        const data = aeds.map(aed => ({
            AED_ID: aed.id.toString(),
            foundation: aed.foundation || '',
            address: aed.address || '',
            latitude: aed.latitude,
            longitude: aed.longitude,
            availability: aed.availability || '',
            aed_webpage: aed.aed_webpage || ''
        }));
        
        await fs.writeFile(this.inputFile, JSON.stringify(data, null, 2));
        console.log(`💾 Saved ${data.length} AEDs to temporary file`);
    }

    async runPythonParser() {
        return new Promise((resolve, reject) => {
            console.log('🐍 Starting Python availability parser...');
            
            const pythonCmd = process.platform === 'win32' ? 'python' : 'python3';
            const pythonProcess = spawn(pythonCmd, [this.scriptPath]);
            
            let stdout = '';
            let stderr = '';
            
            pythonProcess.stdout.on('data', (data) => {
                const output = data.toString();
                stdout += output;
                if (output.includes('>>>') || output.includes('Process Complete') || output.includes('ERROR')) {
                    console.log(output.trim());
                }
            });
            
            pythonProcess.stderr.on('data', (data) => {
                stderr += data.toString();
            });
            
            pythonProcess.on('close', (code) => {
                if (code === 0) {
                    console.log('✅ Python parser completed successfully');
                    resolve(stdout);
                } else {
                    console.error('❌ Python parser failed:', stderr);
                    reject(new Error(`Python script exited with code ${code}: ${stderr}`));
                }
            });
            
            pythonProcess.on('error', (error) => {
                console.error('❌ Failed to start Python script:', error);
                reject(error);
            });
        });
    }

    async parseAvailability(aeds) {
        try {
            const unparsedStrings = await this.getUnparsedStrings(aeds);
            
            if (unparsedStrings.length === 0) {
                console.log('✅ All availability strings already parsed');
                return await this.loadCache();
            }
            
            console.log(`🔄 Parsing ${unparsedStrings.length} new availability strings...`);
            
            await this.saveAEDsToFile(aeds);
            await this.runPythonParser();
            
            const updatedCache = await this.loadCache();
            console.log(`✅ Availability parsing complete. Total cached: ${Object.keys(updatedCache).length}`);
            
            return updatedCache;
            
        } catch (error) {
            console.error('❌ Error in availability parsing:', error);
            return await this.loadCache();
        }
    }

    async getAvailability(availabilityString) {
        const cache = await this.loadCache();
        return cache[availabilityString] || null;
    }
}

module.exports = AvailabilityParser;