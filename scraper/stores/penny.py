"""
Penny (penny.de/angebote).

Manual + automated testing: the page returns 200 and the full category/
offer-tile markup, but every `.offer-tile` is an empty placeholder
(`<h3 class="offer-tile__headline"></h3>`) - the actual products are filled
in client-side via JavaScript after load, and no public JSON endpoint could
be found in the single small bundled JS module the page references. Without
running a real browser this store cannot currently be scraped reliably, so
it reports status "fehlt" with an empty item list (the app falls back to
estimated prices). Revisit if penny.de ships a public offers API.
"""
from __future__ import annotations

from bs4 import BeautifulSoup

from scraper.webclient import new_session
from scraper.matcher import load_ingredients, match_ingredient, parse_pack_size
from scraper.stores.common import build_items, failed, result

NAME = "Penny"
SOURCE = "https://www.penny.de/angebote"


def scrape():
    session = new_session()
    ingredients = load_ingredients()
    try:
        resp = session.get(SOURCE, timeout=30)
        resp.raise_for_status()
    except Exception as e:  # noqa: BLE001
        return failed(NAME, SOURCE, None, None, reason=f"Abruf fehlgeschlagen: {e}")

    soup = BeautifulSoup(resp.text, "html.parser")
    candidates = []
    for tile in soup.select("article.offer-tile"):
        headline = tile.select_one(".offer-tile__headline")
        unit = tile.select_one(".offer-tile__unit-price")
        price_el = tile.select_one(".bubble__price-value") or tile.select_one(".bubble__price")
        title = headline.get_text(" ", strip=True) if headline else ""
        if not title or not price_el:
            continue
        iid = match_ingredient(title, ingredients)
        if not iid:
            continue
        price_txt = price_el.get_text(strip=True).replace(",", ".")
        import re
        digits = re.sub(r"[^\d.]", "", price_txt)
        if not digits:
            continue
        price = float(digits)
        unit_txt = unit.get_text(" ", strip=True) if unit else ""
        pk = parse_pack_size(unit_txt, ingredients[iid]["unit"])
        if pk is None or pk <= 0:
            continue
        candidates.append({"iid": iid, "product": title, "price": price, "pk": pk, "label": unit_txt or None})

    items = build_items(candidates)
    if not items:
        return failed(
            NAME, SOURCE, None, None,
            reason="Angebotskacheln werden erst per JavaScript befüllt (leere Platzhalter im HTML) - "
                   "ohne echten Browser nicht auslesbar",
        )
    status = "ok" if len(items) >= 8 else "teilweise"
    return result(name=NAME, validFrom=None, validTo=None, status=status, source=SOURCE, items=items)
