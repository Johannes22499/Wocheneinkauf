"""
Edeka Hafenmarkt, Hansaring 52, 48155 Münster (Stroetmann).

Manual + automated testing: edeka.de returns HTTP 403 to plain requests/curl
GETs (bot protection), and the market's own prospectus is only published as
a Stroetmann image-based flyer (no extractable product text). Reports status
"fehlt".
"""
from __future__ import annotations

from scraper.webclient import new_session
from scraper.stores.common import failed

NAME = "Edeka"
SOURCE = "https://www.edeka.de/eh/marktangebote.jsp"
MARKET = "Edeka Hafenmarkt, Hansaring 52, 48155 Münster (Stroetmann)"


def scrape():
    session = new_session()
    try:
        resp = session.get(SOURCE, timeout=20)
        if resp.status_code == 200:
            return failed(NAME, SOURCE, None, None, reason="Zugriff jetzt möglich, aber noch kein Parser implementiert")
    except Exception:  # noqa: BLE001
        pass
    out = failed(NAME, SOURCE, None, None, reason="edeka.de blockiert automatische Zugriffe (HTTP 403) / Prospekt nur als Bild")
    out["market"] = MARKET
    return out
