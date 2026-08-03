"""The one place in this codebase that holds the Supabase service_role key.

Kept entirely separate from `data/supabase_client.py` (anon key, used by
every read path). Everything this client touches is still mediated by
narrow RPCs (`find_location_match`, `upsert_ingested_location`,
`upsert_poi_tile`) rather than raw table writes — see docs/backend/12 and
docs/backend/07's "the app/server never holds more privilege than the
specific thing it needs to do" principle, applied here to the ingestion
pipeline instead of the 3D endpoint.
"""
from __future__ import annotations

from supabase import create_client, Client

from config import Config, require_service_role_key

_admin_client: Client | None = None


def get_admin_client() -> Client:
    global _admin_client
    if _admin_client is None:
        _admin_client = create_client(Config.SUPABASE_URL, require_service_role_key())
    return _admin_client
