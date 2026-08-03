import os
import json
from dotenv import load_dotenv
from supabase import create_client, Client
from google import genai
from pydantic import BaseModel, Field

# Load env
load_dotenv("../.env")

url: str = os.environ.get("SUPABASE_URL")
key: str = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
supabase: Client = create_client(url, key)

client = genai.Client(api_key=os.environ.get("GEMINI_API_KEY"))

class TranslationOutput(BaseModel):
    name: str
    blurb: str = Field(default="")

def translate_text(loc: dict, target_lang: str) -> dict:
    prompt = f"""
    Translate the following location information to {target_lang}.
    It is a curated location in Algeria.
    If the name is a proper noun (e.g. 'Maqam Echahid'), keep it appropriate for the language, or translate if standard.
    
    Name: {loc.get('name')}
    Blurb: {loc.get('blurb', '')}
    
    Return a JSON object with 'name' and 'blurb'.
    """
    
    generation_config = {
        'max_output_tokens': 2048,
        'temperature': 0.1,
        'response_mime_type': 'application/json',
        'response_schema': TranslationOutput
    }
    
    response = client.models.generate_content(
        model='gemini-2.5-flash',
        contents=prompt,
        config=generation_config
    )
    
    return json.loads(response.text)

def main():
    print("Fetching curated locations (English translations)...")
    res = supabase.table("location_translations").select("location_id, name, blurb").eq("locale", "en").execute()
    locations = res.data
    
    for loc in locations:
        print(f"Translating: {loc['name']}")
        for lang in ['fr', 'ar']:
            existing = supabase.table("location_translations").select("location_id").eq("location_id", loc["location_id"]).eq("locale", lang).execute()
            if existing.data:
                print(f"  [{lang}] already exists, skipping.")
                continue
            
            print(f"  [{lang}] Translating...")
            try:
                translated = translate_text(loc, "French" if lang == 'fr' else "Arabic (Modern Standard)")
                supabase.table("location_translations").insert({
                    "location_id": loc["location_id"],
                    "locale": lang,
                    "name": translated.get("name") or loc.get("name"),
                    "blurb": translated.get("blurb")
                }).execute()
                print(f"  [{lang}] Saved.")
            except Exception as e:
                print(f"  [{lang}] Error: {e}")

if __name__ == "__main__":
    main()
