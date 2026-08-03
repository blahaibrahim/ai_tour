"""Wikimedia Commons file resolution — license and attribution metadata for
a Commons filename, used by `photos.py`.
"""
from __future__ import annotations

import logging
import re

import requests

from config import Config

logger = logging.getLogger(__name__)

TIMEOUT_S = 15
_TAG_RE = re.compile(r"<[^>]+>")


def _user_agent() -> str:
    contact = Config.OVERPASS_CONTACT or "no-contact-configured"
    return f"ai_tour_ingestion/1.0 ({contact})"


def _strip_html(value: str | None) -> str | None:
    """Commons' extmetadata fields (Artist, Credit) come back as HTML
    fragments (`<a href=...>Name</a>`) — the app displays these as plain
    text, so this is stripped once here rather than at every call site."""
    if not value:
        return None
    return _TAG_RE.sub("", value).strip() or None


def resolve_commons_file(filename: str) -> dict | None:
    """Given a bare Commons filename (no `File:` prefix required), returns
    {"url", "attribution", "license", "source_url"} or None if the file
    doesn't exist or has no usable license metadata. Every field here is
    exactly what docs/backend/05's storage plan and docs/backend/11's
    checklist require to display attribution alongside the image — never
    store a photo_url without also storing where it came from."""
    try:
        resp = requests.get(
            "https://commons.wikimedia.org/w/api.php",
            params={
                "action": "query",
                "titles": f"File:{filename}",
                "prop": "imageinfo",
                "iiprop": "url|extmetadata",
                "iiurlwidth": "800",
                "format": "json",
            },
            headers={"User-Agent": _user_agent()},
            timeout=TIMEOUT_S,
        )
        resp.raise_for_status()
        pages = resp.json()["query"]["pages"]
    except (requests.RequestException, ValueError, KeyError) as e:
        logger.warning("Commons imageinfo lookup failed for %r: %s", filename, e)
        return None

    page = next(iter(pages.values()), {})
    imageinfo = page.get("imageinfo")
    if not imageinfo:
        return None

    info = imageinfo[0]
    meta = info.get("extmetadata", {})
    artist = _strip_html(meta.get("Artist", {}).get("value"))
    credit = _strip_html(meta.get("Credit", {}).get("value"))
    license_name = meta.get("LicenseShortName", {}).get("value")

    attribution = artist or credit
    if not attribution or not license_name:
        # No usable attribution/license metadata — treat as unusable rather
        # than publishing an image we can't credit. Matches the "never
        # display a photo without its attribution" rule this module exists
        # to enforce.
        return None

    return {
        "url": info.get("thumburl", info["url"]),
        "attribution": attribution,
        "license": license_name,
        "source_url": info.get("descriptionurl", info["url"]),
    }
