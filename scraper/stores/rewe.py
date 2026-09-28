"""
Rewe (rewe.de/angebote) - nearest branch Rewe Wolbecker Str. 44, Münster.

Manual + automated testing: rewe.de returns HTTP 403 to plain requests/curl
GETs (bot protection). Reports status "fehlt".
"""
from __future__ import annotations

from scraper.webclient import new_session
from scraper.stores.common import failed

NAME = "Rewe"
SOURCE = "https://www.rewe.de/angebote"
MARKET = "Rewe Wolbecker Str. 44, Münster"


def scrape():
    session = new_session()
    try:
        resp = session.get(SOURCE, timeout=20)
        if resp.status_code == 200:
            return failed(NAME, SOURCE, None, None, reason="Zugriff jetzt möglich, aber noch kein Parser implementiert")
    except Exception:  # noqa: BLE001
        pass
    out = failed(NAME, SOURCE, None, None, reason="rewe.de blockiert automatische Zugriffe (HTTP 403)")
    out["market"] = MARKET
    return out
