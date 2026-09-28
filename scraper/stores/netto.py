"""
Netto Marken-Discount (netto-online.de).

Manual + automated testing: the site returns HTTP 403 to a plain requests /
curl GET, with and without extra Accept/Accept-Language/Sec-Fetch headers -
it needs a real browser (bot detection). Reports status "fehlt".
"""
from __future__ import annotations

from scraper.webclient import new_session
from scraper.stores.common import failed

NAME = "Netto"
SOURCE = "https://www.netto-online.de/"


def scrape():
    session = new_session()
    try:
        resp = session.get(SOURCE, timeout=20)
        if resp.status_code == 200:
            # Site unblocked itself - but we have no parser for its markup yet.
            return failed(NAME, SOURCE, None, None, reason="Zugriff jetzt möglich, aber noch kein Parser implementiert")
    except Exception:  # noqa: BLE001
        pass
    return failed(NAME, SOURCE, None, None, reason="netto-online.de blockiert automatische Zugriffe (HTTP 403)")
