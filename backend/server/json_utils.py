"""Defensive JSON parsing for LLM output.

Models behind a router sometimes wrap JSON in markdown fences or add stray
prose despite being told not to. Try a straight parse first, then salvage a
fenced or embedded object before giving up.
"""
from __future__ import annotations

import json
import re


def extract_json(text: str) -> dict:
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fenced:
        try:
            return json.loads(fenced.group(1))
        except json.JSONDecodeError:
            pass

    brace = re.search(r"\{.*\}", text, re.DOTALL)
    if brace:
        try:
            return json.loads(brace.group(0))
        except json.JSONDecodeError:
            pass

    raise ValueError("Could not parse a JSON object out of the LLM response")
