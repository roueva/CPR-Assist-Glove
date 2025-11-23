import json
import os
import time
import requests
import random

# --- Configuration ---

# ✅ Get API key from environment variable
API_KEY = os.environ.get('GEMINI_API_KEY', '')

if not API_KEY:
    print("❌ ERROR: GEMINI_API_KEY environment variable not set!")
    print("   Please add it to your .env file or Railway environment variables")
    exit(1)

BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

# ✅ Dynamic path resolution
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, '../data')

# Ensure data directory exists
os.makedirs(DATA_DIR, exist_ok=True)

INPUT_FILE = os.path.join(DATA_DIR, 'aed_greece_current.json')
CACHE_FILE = os.path.join(DATA_DIR, 'parsed_availability_map.json')

# --- LLM Prompt & Schema ---

SYSTEM_PROMPT = """
Role: You are an expert Data Extraction Bot.
Task: Your mission is to parse unstructured text strings in Greek that describe the availability of AEDs. You must convert each string into a strict JSON format, following the schema.

Field Definitions & Logic Rules:
- status:
  - "parsed": Use when you can extract specific time/day rules.
  - "uncertain": Use for vague/conditional availability (e.g., "By phone", "During games").
  - "closed_for_use": Use for private use only (e.g., "For the rescue team").
- is_24_7:
  - true ONLY if it explicitly says "24/7" or "όλο το 24ωρο" AND has no other restrictions.
- uncertain_reason:
  - If status is "uncertain", provide a brief English explanation (e.g., "During games/events").
- rules.days:
  - 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun.
  - "Καθημερινά" (Daily) = [1, 2, 3, 4, 5, 6, 7]
  - "Δευτέρα - Παρασκευή" (Mon-Fri) = [1, 2, 3, 4, 5]
  - "Σαββατοκύριακο" (Weekend) = [6, 7]
- rules.open_time / rules.close_time:
  - Always use 24-hour HH:mm format.
  - 9:30 -> "09:30"
  - 4:00 μ.μ. (4 PM) -> "16:00"
  - 12:00 μ.μ. (Noon) -> "12:00"
  - Overnight (e.g., "20:00 - 04:00"): Use "20:00" and "04:00".
  - 24 Hours: Use "00:00" and "24:00".
- rules.start_month / rules.end_month:
  - Use 1-12 for months.
  - Wrap-around (e.g., "October to May"): Use start_month: 10, end_month: 5.
  - "School months": Assume start_month: 9, end_month: 6.
"""

JSON_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "original_text": {"type": "STRING"},
        "status": {
            "type": "STRING",
            "enum": ["parsed", "uncertain", "closed_for_use"]
        },
        "is_24_7": {"type": "BOOLEAN"},
        "uncertain_reason": {"type": "STRING"},
        "rules": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "days": {
                        "type": "ARRAY",
                        "items": {"type": "INTEGER"}
                    },
                    "start_month": {"type": "INTEGER"},
                    "start_day": {"type": "INTEGER"},
                    "end_month": {"type": "INTEGER"},
                    "end_day": {"type": "INTEGER"},
                    "open_time": {"type": "STRING"},
                    "close_time": {"type": "STRING"}
                },
                "propertyOrdering": ["days", "start_month", "start_day", "end_month", "end_day", "open_time", "close_time"]
            }
        }
    },
    "required": ["original_text", "status", "is_24_7", "rules"],
    "propertyOrdering": ["original_text", "status", "is_24_7", "uncertain_reason", "rules"]
}


def load_unique_strings(filepath):
    """Reads the input JSON file and returns a set of unique availability strings."""
    if not os.path.exists(filepath):
        print(f"Error: Input file '{filepath}' not found.")
        return set()

    print(f"Loading AED data from '{filepath}'...")
    with open(filepath, 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    unique_strings = set()
    for item in data:
        availability = item.get('availability')
        if availability and availability.strip():
            unique_strings.add(availability.strip())
            
    print(f"Found {len(unique_strings)} unique availability strings to process.")
    return unique_strings

def load_cache(cache_filepath):
    if os.path.exists(cache_filepath):
        print(f"Loading cache from '{cache_filepath}'...")
        try:
            with open(cache_filepath, 'r', encoding='utf-8') as f:
                return json.load(f)
        except json.JSONDecodeError:
            return {}
    return {}

def save_to_cache(cache_filepath, data):
    with open(cache_filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def find_best_model():
    """Automatically queries the API to find a working model."""
    print("Contacting Google API to find available models...")
    url = f"{BASE_URL}/models?key={API_KEY}"
    try:
        response = requests.get(url)
        if response.status_code != 200:
            print(f"Error listing models: {response.status_code} {response.text}")
            return None
        
        models = response.json().get('models', [])
        valid_models = [m['name'] for m in models if 'generateContent' in m.get('supportedGenerationMethods', [])]
        
        # Priority Change: Targeting "LITE" models now!
        preferences = [
            'models/gemini-2.5-flash-lite-preview-06-17', # 👈 NEW PRIORITY 1
            'models/gemini-2.0-flash-lite-preview-02-05', # 👈 NEW PRIORITY 2
            'models/gemini-2.0-flash-lite-001',           # 👈 NEW PRIORITY 3
            'models/gemini-2.0-flash-lite',               # 👈 NEW PRIORITY 4
            'models/gemini-1.5-flash',                    # Fallback
            'models/gemini-1.5-flash-001',
            'models/gemini-1.0-pro'
        ]
        
        # 1. Try to find a preferred model
        for pref in preferences:
            if pref in valid_models:
                print(f"\n>>> SELECTED MODEL: {pref}")
                return pref
        
        # 2. If none of the preferred ones exist, take the first valid one
        if valid_models:
            fallback = valid_models[0]
            print(f"\n>>> No preferred models found. Using fallback: {fallback}")
            return fallback
            
        print("No models found that support generateContent.")
        return None

    except Exception as e:
        print(f"Error finding models: {e}")
        return None

def parse_string_with_gemini(text_to_parse, model_url, max_retries=5):
    payload = {
        "contents": [
            {"parts": [{"text": text_to_parse}]}
        ],
        "systemInstruction": {
            "parts": [{"text": SYSTEM_PROMPT}]
        },
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": JSON_SCHEMA,
            "temperature": 0.0
        }
    }
    
    for attempt in range(max_retries):
        try:
            response = requests.post(model_url, json=payload, timeout=60)
            
            # Rate limit handling
            if response.status_code in (429, 500, 503):
                # Base wait of 15 seconds 
                base_wait = 15
                wait_time = (base_wait ** (1)) + random.uniform(1, 5)
                
                if response.status_code == 429:
                     print(f"\n      [429 ERROR DETAILS]: {response.text[:200]}...") 
                     wait_time = wait_time * (attempt + 1)

                print(f"      ...API Error ({response.status_code}). Retrying in {wait_time:.1f}s...")
                time.sleep(wait_time)
                continue
                
            if response.status_code != 200:
                print(f"      ...API Error ({response.status_code}): {response.text}")
                return None
            
            result = response.json()
            json_string = result['candidates'][0]['content']['parts'][0]['text']
            return json.loads(json_string)

        except Exception as e:
            print(f"      ...Error: {e}")
            time.sleep(5)
            
    return None

def main():
    # 1. Find a working model first
    model_name = find_best_model()
    if not model_name:
        print("Could not find a valid Gemini model to use. Please check your API key.")
        return

    # Construct the specific URL for the found model
    current_api_url = f"{BASE_URL}/{model_name}:generateContent?key={API_KEY}"
    
    # 2. Load Data
    unique_strings = load_unique_strings(INPUT_FILE)
    if not unique_strings:
        return

    # 3. Load Cache
    cache = load_cache(CACHE_FILE)
    
    # 4. Process
    for i, text in enumerate(unique_strings):
        print(f"\n[{i+1}/{len(unique_strings)}] Processing:")
        print(f"  > {text}")
        
        if text in cache:
            print("  ...Result found in cache. Skipping.")
            continue
            
        parsed_data = parse_string_with_gemini(text, current_api_url)
        
        if parsed_data:
            cache[text] = parsed_data
            save_to_cache(CACHE_FILE, cache)
            print("  ...Success.")
        else:
            print("  ...Failed.")
            
        # 10 seconds delay to be safe
        print("  ...Waiting 10s...")
        time.sleep(10.0)
            
    print(f"\n--- Process Complete ---")

if __name__ == "__main__":
    main()