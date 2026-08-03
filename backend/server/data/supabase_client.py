"""Cached Supabase client for read-only catalogue access.

This module intentionally exposes nothing beyond a client getter — every
actual query lives in `locations_repo.py`, which is also where the
fallback-to-curated-data behaviour lives (see docs/backend/12: "the curated
8 are the floor. Never show an empty map.").
"""
from __future__ import annotations

from supabase import create_client, Client

from config import Config

_client: Client | None = None


def is_configured() -> bool:
    return bool(Config.SUPABASE_URL and Config.SUPABASE_ANON_KEY)


def get_client() -> Client:
    global _client
    if not is_configured():
        raise RuntimeError(
            "SUPABASE_URL / SUPABASE_ANON_KEY are not set. Add them to backend/.env."
        )
    if _client is None:
        _client = create_client(Config.SUPABASE_URL, Config.SUPABASE_ANON_KEY)
    return _client
