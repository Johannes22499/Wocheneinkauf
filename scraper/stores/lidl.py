"""
Lidl - nearest branch Weseler Str. 109, 48151 Münster.

Manual testing: lidl.de/de/angebote/ redirects to the homepage, and the
weekly offers live only inside an image-based flyer viewer
(lidl.de/l/prospekte/.../view/flyer/...) with no extractable product text -
just page images. No public JSON product feed was found. Reports status
"fehlt" so the app falls back to estimated prices.
"""
from __future__ import annotations

from scraper.webclient import new_session
from scraper.stores.common import failed

NAME = "Lidl"
SOURCE = "https://www.lidl.de/c/online-prospekte/s10005610"
MARKET = "Lidl Weseler Str. 109, 48151 Münster"


def scrape():
    session = new_session()
    try:
        resp = session.get(SOURCE, timeout=30)
        resp.raise_for_status()
    except Exception as e:  # noqa: BLE001
        return failed(NAME, SOURCE, None, None, reason=f"Abruf fehlgeschlagen: {e}")

    out = failed(
        NAME, SOURCE, None, None,
        reason="Angebote nur als Bildprospekt (Online-Flyer), kein auslesbarer Produkttext gefunden",
    )
    out["market"] = MARKET
    return out
