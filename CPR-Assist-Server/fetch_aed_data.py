import requests
import pandas as pd
import hashlib


# Overpass API URL
OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# OpenAEDMap Export URL
OPENAEDMAP_URL = "https://openaedmap.org/api/v1/countries/GR.geojson"

# Your Backend API Endpoint
BACKEND_URL = "http://localhost:8080/aed/bulk-update"
# BACKEND_URL = "https://cpr-assist-app.up.railway.app/aed/bulk-update"


# Overpass API Query for AEDs in Greece & Cyprus
OVERPASS_QUERY = """
[out:json][timeout:60];
(
  node["emergency"="defibrillator"](34.6,19.4,41.8,29.7);
  node["healthcare"="defibrillator"](34.6,19.4,41.8,29.7);
  node["medical_equipment"="aed"](34.6,19.4,41.8,29.7);
  node["amenity"="aed"](34.6,19.4,41.8,29.7);
  
  node["emergency"="defibrillator"](34.5,32.2,35.7,34.6);
  node["healthcare"="defibrillator"](34.5,32.2,35.7,34.6);
  node["medical_equipment"="aed"](34.5,32.2,35.7,34.6);
  node["amenity"="aed"](34.5,32.2,35.7,34.6);
);
out body;
"""

def fetch_overpass_data():
    """Fetch AED locations from Overpass API"""
    try:
        response = requests.post(OVERPASS_URL, data=OVERPASS_QUERY, timeout=60)
        response.raise_for_status()
        elements = response.json().get("elements", [])
        print(f"✅ Fetched {len(elements)} AEDs from Overpass API.")
        return [
            {
                "id": aed.get("id"),
                "latitude": aed.get("lat"),
                "longitude": aed.get("lon"),
                "name": aed.get("tags", {}).get("name", "Unknown"),
                "address": aed.get("tags", {}).get("addr:full", "unknown"),
                "emergency": "defibrillator",
                "operator": aed.get("tags", {}).get("operator", "Unknown"),
                "indoor": aed.get("tags", {}).get("indoor", "no") == "yes",
                "access": aed.get("tags", {}).get("access", "unknown"),
                "defibrillator_location": aed.get("tags", {}).get("defibrillator:location", "Not specified"),
                "level": aed.get("tags", {}).get("level", "unknown"),
                "opening_hours": aed.get("tags", {}).get("opening_hours", "unknown"),
                "phone": aed.get("tags", {}).get("phone", "unknown"),
                "wheelchair": aed.get("tags", {}).get("wheelchair", "unknown"),
                "source": "Overpass API"
            }
            for aed in elements
        ]
    except requests.exceptions.RequestException as e:
        print(f"❌ Overpass API request failed: {e}")
        return []

def fetch_openaedmap_data():
    """Fetch AED locations from OpenAEDMap"""
    try:
        response = requests.get(OPENAEDMAP_URL)
        response.raise_for_status()
        geojson_data = response.json()
        features = geojson_data.get("features", [])
        print(f"✅ Fetched {len(features)} AEDs from OpenAEDMap.")
        return [
            {
                "id": feature["properties"].get("@id"),
                "latitude": feature["geometry"]["coordinates"][1],
                "longitude": feature["geometry"]["coordinates"][0],
                "name": feature["properties"].get("name", "Unknown"),
                "address": feature["properties"].get("address", "unknown"),
                "emergency": "defibrillator",
                "operator": feature["properties"].get("operator", "Unknown"),
                "indoor": feature["properties"].get("indoor", "no") == "yes",
                "access": feature["properties"].get("access", "unknown"),
                "defibrillator_location": feature["properties"].get("defibrillator:location", "Not specified"),
                "level": feature["properties"].get("level", "unknown"),
                "opening_hours": feature["properties"].get("opening_hours", "unknown"),
                "phone": feature["properties"].get("phone", "unknown"),
                "wheelchair": feature["properties"].get("wheelchair", "unknown"),
                "source": "OpenAEDMap"
            }
            for feature in features
        ]
    except requests.exceptions.RequestException as e:
        print(f"❌ OpenAEDMap request failed: {e}")
        return []


# Function to generate a unique ID based on location
def generate_id(aed):
    """Generate a unique ID for an AED based on latitude & longitude."""
    unique_string = f"{aed['latitude']},{aed['longitude']}"
    return int(hashlib.md5(unique_string.encode()).hexdigest(), 16) % (10**9)  # Convert to a 9-digit integer


def merge_and_send_data():
    """Merge data, generate IDs, and send it to the backend"""
    overpass_data = fetch_overpass_data()
    openaedmap_data = fetch_openaedmap_data()

    print(f"Overpass AEDs: {len(overpass_data)}, OpenAEDMap AEDs: {len(openaedmap_data)}")

    all_aeds = {f"{aed['latitude']},{aed['longitude']}": aed for aed in overpass_data + openaedmap_data}

    # ✅ Assign unique IDs to AEDs that don't have one
    for aed in all_aeds.values():
        if not aed.get("id"):
            aed["id"] = generate_id(aed)  # Generate a unique ID based on location

    final_data = {"aeds": list(all_aeds.values())}

    print(f"Sending {len(final_data['aeds'])} AEDs to backend...")

    try:
        response = requests.post(BACKEND_URL, json=final_data, headers={'Content-Type': 'application/json'}, timeout=30)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to update AED data: {e}")


def save_to_excel(aed_data):
    """Save AED data to an Excel file"""
    df = pd.DataFrame(aed_data)
    df.to_excel("aed_locations.xlsx", index=False)
    print("AED data saved to aed_locations.xlsx")

if __name__ == "__main__":
    aed_data = merge_and_send_data()
    save_to_excel(aed_data)
