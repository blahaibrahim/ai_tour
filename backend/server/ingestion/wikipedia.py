"""Wikipedia summary + pageviews — docs/backend/12's real blurb source and
its best free popularity signal.
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta

import requests

from config import Config

logger = logging.getLogger(__name__)

TIMEOUT_S = 15


def _user_agent() -> str:
    contact = Config.OVERPASS_CONTACT or "no-contact-configured"
    return f"ai_tour_ingestion/1.0 ({contact})"


def fetch_summary(title: str, lang: str = "en") -> dict | None:
    """Returns {"extract", "thumbnail_url", "original_url"} (the latter two
    `None` if the article has no lead image) or None if the article doesn't
    exist / the request fails. A missing summary is not fatal to ingestion —
    the POI still gets an OSM-derived blurb.

    Both a thumbnail and the original are returned because they serve
    different purposes: `thumbnail_url` is what gets stored and displayed
    (a few hundred KB, this app's use case doesn't need more); `original_url`
    is only used to recover the underlying Commons filename in `photos.py`,
    since the thumbnail URL's `/330px-` size prefix makes that extraction
    more fragile than it needs to be.
    """
    try:
        resp = requests.get(
            f"https://{lang}.wikipedia.org/api/rest_v1/page/summary/{title}",
            headers={"User-Agent": _user_agent()},
            timeout=TIMEOUT_S,
        )
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        data = resp.json()
    except (requests.RequestException, ValueError) as e:
        logger.warning("Wikipedia summary fetch failed for %r: %s", title, e)
        return None

    extract = data.get("extract")
    if not extract:
        return None

    return {
        "extract": extract,
        "thumbnail_url": (data.get("thumbnail") or {}).get("source"),
        "original_url": (data.get("originalimage") or {}).get("source"),
    }


def fetch_pageviews_30d(title: str, lang: str = "en") -> int | None:
    """Total pageviews over the trailing 30 days, ending yesterday (today is
    still accumulating and often isn't fully aggregated yet).

    Originally tried `monthly` granularity with the two dates set to the
    first-of-month boundaries — that turned out to be a real bug, not a
    style choice: it 400'd against the live API during ingestion testing
    (`.../monthly/20260701/20260701`). Rather than guess at the exact
    monthly-endpoint boundary convention against a rate-limited API, this
    switched to `daily` granularity summed over the window — unambiguous,
    and a more literal match for what "30d" in the field name actually means.
    """
    yesterday = datetime.utcnow().date() - timedelta(days=1)
    window_start = yesterday - timedelta(days=29)  # 30 days inclusive of yesterday

    start = window_start.strftime("%Y%m%d")
    end = yesterday.strftime("%Y%m%d")

    url = (
        "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/"
        f"{lang}.wikipedia/all-access/user/{title}/daily/{start}/{end}"
    )
    try:
        resp = requests.get(url, headers={"User-Agent": _user_agent()}, timeout=TIMEOUT_S)
        if resp.status_code == 404:
            return None
        resp.raise_for_status()
        items = resp.json().get("items", [])
    except (requests.RequestException, ValueError) as e:
        logger.warning("Wikipedia pageviews fetch failed for %r: %s", title, e)
        return None

    if not items:
        return None
    return sum(item.get("views", 0) for item in items)
