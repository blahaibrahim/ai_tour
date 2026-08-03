import os
from pathlib import Path

from dotenv import load_dotenv

# backend/.env, not backend/server/.env — this app lives alongside hunyuan2.1/
# as a second component of the same backend/ folder.
BACKEND_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BACKEND_DIR / ".env")


class Config:
    GROQ_API_KEY = os.environ.get("GROQ_API_KEY")
    GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")
    LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "https://api.groq.com/openai/v1")
    LLM_MODEL = os.environ.get("LLM_MODEL", "qwen/qwen3.6-27b")

    # The anon key: this is what every *read* path uses (locations_repo.py).
    # RLS grants anon+authenticated select on the public catalogue and
    # nothing else — see docs/backend/02.
    SUPABASE_URL = os.environ.get("SUPABASE_URL")
    SUPABASE_ANON_KEY = os.environ.get("SUPABASE_ANON_KEY")

    # The service_role key: held only by this trusted server, used only by
    # the ingestion module (ingestion/supabase_admin.py) to write newly
    # discovered POIs. Every write it performs still goes through narrow,
    # validated RPCs (upsert_ingested_location, upsert_poi_tile) rather than
    # raw table access — see docs/backend/12. Never let this reach the app.
    SUPABASE_SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

    OVERPASS_CONTACT = os.environ.get("OVERPASS_CONTACT", "")

    PORT = int(os.environ.get("PORT", 8000))
    DEBUG = os.environ.get("FLASK_DEBUG", "0") == "1"

    MODAL_PROXY_KEY = os.environ.get("MODAL_PROXY_KEY")
    MODAL_PROXY_SECRET = os.environ.get("MODAL_PROXY_SECRET")
    MODAL_SUBMIT_URL = os.environ.get("MODAL_SUBMIT_URL")


def require_llm_key() -> str:
    if not Config.GROQ_API_KEY:
        raise RuntimeError(
            "GROQ_API_KEY is not set. Add it to backend/.env."
        )
    return Config.GROQ_API_KEY

def require_gemini_key() -> str:
    if not Config.GEMINI_API_KEY:
        raise RuntimeError(
            "GEMINI_API_KEY is not set. Add it to backend/.env."
        )
    return Config.GEMINI_API_KEY


def require_service_role_key() -> str:
    if not Config.SUPABASE_SERVICE_ROLE_KEY:
        raise RuntimeError(
            "SUPABASE_SERVICE_ROLE_KEY is not set. Add it to backend/.env — "
            "find it in the Supabase dashboard under Project Settings > API "
            "(the 'service_role' secret key, not the anon/publishable one). "
            "Only the POI ingestion pipeline needs this; every other route "
            "works fine without it."
        )
    return Config.SUPABASE_SERVICE_ROLE_KEY


def require_modal_keys() -> tuple[str, str, str]:
    if not (Config.MODAL_PROXY_KEY and Config.MODAL_PROXY_SECRET and Config.MODAL_SUBMIT_URL):
        raise RuntimeError(
            "MODAL_PROXY_KEY, MODAL_PROXY_SECRET, or MODAL_SUBMIT_URL is not set. "
            "Add them to backend/.env to use the 3D generation endpoint."
        )
    return Config.MODAL_PROXY_KEY, Config.MODAL_PROXY_SECRET, Config.MODAL_SUBMIT_URL
