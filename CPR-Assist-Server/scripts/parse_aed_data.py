import json
import os
import time
import requests
import random
import psycopg2

# --- Configuration ---
API_KEY = os.environ.get('GROQ_API_KEY', '')
if not API_KEY:
    print("❌ ERROR: GROQ_API_KEY environment variable not set!")
    exit(1)

MODEL = "llama-3.3-70b-versatile"
GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, '../data')
os.makedirs(DATA_DIR, exist_ok=True)

INPUT_FILE = os.path.join(DATA_DIR, 'aed_greece_current.json')
CACHE_FILE = os.path.join(DATA_DIR, 'parsed_availability_map.json')

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
  - 9:30 -> "09:30", 4:00 μ.μ. -> "16:00", 12:00 μ.μ. -> "12:00"
  - Overnight (e.g., "20:00 - 04:00"): Use "20:00" and "04:00".
  - 24 Hours: Use "00:00" and "24:00".
- rules.start_month / rules.end_month:
  - Use 1-12 for months.
  - Wrap-around (e.g., "October to May"): start_month: 10, end_month: 5.
  - "School months": start_month: 9, end_month: 6.

Respond ONLY with valid JSON matching this exact structure, no extra text:
{
  "original_text": "the input text here",
  "status": "parsed",
  "is_24_7": false,
  "uncertain_reason": "",
  "rules": [
    {
      "days": [1,2,3,4,5],
      "start_month": null,
      "end_month": null,
      "open_time": "09:00",
      "close_time": "17:00"
    }
  ]
}
"""

def load_unique_strings(filepath):
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
        try:
            with open(cache_filepath, 'r', encoding='utf-8') as f:
                return json.load(f)
        except json.JSONDecodeError:
            return {}
    return {}

def save_to_cache(cache_filepath, data):
    with open(cache_filepath, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def load_from_db():
    database_url = os.environ.get('DATABASE_URL', '')
    if not database_url:
        return {}
    if database_url.startswith('postgres://'):
        database_url = database_url.replace('postgres://', 'postgresql://', 1)
    try:
        conn = psycopg2.connect(database_url, sslmode='require')
        cur = conn.cursor()
        cur.execute('SELECT availability_text, parsed_data FROM availability_cache')
        rows = cur.fetchall()
        cur.close()
        conn.close()
        if rows:
            cache = {row[0]: row[1] for row in rows}
            print(f"📦 Loaded {len(cache)} entries from database")
            return cache
    except Exception as e:
        print(f"⚠️ Could not load from database: {e}")
    return {}

def save_to_db(text, data):
    database_url = os.environ.get('DATABASE_URL', '')
    if not database_url:
        return
    if database_url.startswith('postgres://'):
        database_url = database_url.replace('postgres://', 'postgresql://', 1)
    try:
        conn = psycopg2.connect(database_url, sslmode='require')
        cur = conn.cursor()
        data_json = json.dumps(data, ensure_ascii=False)
        cur.execute(
            """INSERT INTO availability_cache (availability_text, parsed_data)
               VALUES (%s, %s)
               ON CONFLICT (availability_text)
               DO UPDATE SET parsed_data = %s, parsed_at = NOW()""",
            [text, data_json, data_json]
        )
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        print(f"      ...DB save FAILED: {e}")

def save_all_to_db(cache_dict):
    database_url = os.environ.get('DATABASE_URL', '')
    if not database_url:
        return
    if database_url.startswith('postgres://'):
        database_url = database_url.replace('postgres://', 'postgresql://', 1)
    try:
        conn = psycopg2.connect(database_url, sslmode='require')
        cur = conn.cursor()
        for text, data in cache_dict.items():
            data_json = json.dumps(data, ensure_ascii=False)
            cur.execute(
                """INSERT INTO availability_cache (availability_text, parsed_data)
                   VALUES (%s, %s)
                   ON CONFLICT (availability_text)
                   DO UPDATE SET parsed_data = %s, parsed_at = NOW()""",
                [text, data_json, data_json]
            )
        conn.commit()
        cur.close()
        conn.close()
        print(f"✅ Saved {len(cache_dict)} entries to DB")
    except Exception as e:
        print(f"❌ Bulk DB save FAILED: {e}")

def parse_string_with_groq(text_to_parse, max_retries=5):
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text_to_parse}
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.0,
        "max_tokens": 1000
    }

    for attempt in range(max_retries):
        try:
response = requests.post(GROQ_URL, headers=headers, json=payload, timeout=(10, 30))

            if response.status_code == 429:
                wait_time = 30 * (attempt + 1) + random.uniform(1, 5)
                print(f"      ...Rate limit hit. Retrying in {wait_time:.1f}s...")
                time.sleep(wait_time)
                continue

            if response.status_code != 200:
                print(f"      ...API Error ({response.status_code}): {response.text}")
                return None

            result = response.json()
            content = result['choices'][0]['message']['content']
            return json.loads(content)

        except Exception as e:
            print(f"      ...Error: {e}")
            time.sleep(5)
    return None

def main():
    # Test DB connection
    database_url = os.environ.get('DATABASE_URL', '')
    print(f"      ...DATABASE_URL present: {bool(database_url)}")
    if database_url:
        db_url = database_url.replace('postgres://', 'postgresql://', 1)
        try:
            conn = psycopg2.connect(db_url, sslmode='require')
            cur = conn.cursor()
            cur.execute('SELECT COUNT(*) FROM availability_cache')
            count = cur.fetchone()[0]
            cur.close()
            conn.close()
            print(f"      ...DB connection OK, availability_cache has {count} rows")
        except Exception as e:
            print(f"      ...DB connection FAILED: {e}")

    print(f">>> USING MODEL: {MODEL} via Groq")

    unique_strings = load_unique_strings(INPUT_FILE)
    if not unique_strings:
        return

    cache = load_from_db()
    if not cache:
        cache = load_cache(CACHE_FILE)

    total = len(unique_strings)
    skipped = sum(1 for t in unique_strings if t in cache)
    print(f"📊 {total} strings total, {skipped} already cached, {total - skipped} to parse")

    for i, text in enumerate(unique_strings):
        print(f"\n[{i+1}/{total}] Processing:")
        print(f"  > {text}")

        if text in cache:
            print("  ...Result found in cache. Skipping.")
            continue

        parsed_data = parse_string_with_groq(text)

        if parsed_data:
            cache[text] = parsed_data
            save_to_cache(CACHE_FILE, cache)
            save_to_db(text, parsed_data)
            print("  ...Success.")
        else:
            print("  ...Failed.")

        print("  ...Waiting 3s...")
        time.sleep(3.0)

    save_all_to_db(cache)
    print(f"\n--- Process Complete ---")

if __name__ == "__main__":
    main()