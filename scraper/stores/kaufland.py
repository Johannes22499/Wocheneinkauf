"""
Kaufland - filiale.kaufland.de/angebote/uebersicht.html is server-rendered
(no JS execution needed): every offer tile is plain HTML with class
`k-product-tile`. The page is the generic national overview (no store/PLZ
selection is needed to load it), which matches what manual curl testing
found (200 OK, ~5 MB HTML).
"""
from __future__ import annotations

import re

from bs4 import BeautifulSoup

from scraper.webclient import new_session
from scraper.matcher import load_ingredients, match_ingredient, parse_pack_size
from scraper.stores.common import build_items, failed, result

NAME = "Kaufland"
SOURCE = "https://filiale.kaufland.de/angebote/uebersicht.html"

_DATE_RANGE_RE = re.compile(r"G[uü]ltig\s+vom\s+(\d{1,2}\.\d{1,2})\.?\s+bis\s+(\d{1,2}\.\d{1,2})\.?", re.IGNORECASE)


def _to_iso(dm: str, year: int) -> str:
    day, month = dm.split(".")
    return f"{year}-{int(month):02d}-{int(day):02d}"


def _find_validity(soup: BeautifulSoup, year: int):
    text = soup.get_text(" ", strip=True)
    m = _DATE_RANGE_RE.search(text)
    if not m:
        return None, None
    return _to_iso(m.group(1), year), _to_iso(m.group(2), year)


def _clean_unit_price_text(t: str) -> str:
    # "je 150-g-Becher" / "je 26 - 85-g-Beutel" / "je Stück" -> normalise for parse_pack_size
    t = t.replace("je ", "")
    return t


def scrape():
    session = new_session()
    ingredients = load_ingredients()

    try:
        resp = session.get(SOURCE, timeout=30)
        resp.raise_for_status()
    except Exception as e:  # noqa: BLE001
        return failed(NAME, SOURCE, None, None, reason=f"Abruf fehlgeschlagen: {e}")

    soup = BeautifulSoup(resp.text, "html.parser")
    import datetime
    valid_from, valid_to = _find_validity(soup, datetime.date.today().year)

    tiles = soup.select("a.k-product-tile")
    if not tiles:
        return failed(NAME, SOURCE, valid_from, valid_to, reason="Keine Produkt-Kacheln gefunden (Seitenstruktur geändert?)")

    candidates = []
    for tile in tiles:
        title_el = tile.select_one(".k-product-tile__title")
        subtitle_el = tile.select_one(".k-product-tile__subtitle")
        unit_el = tile.select_one(".k-product-tile__unit-price")
        price_el = tile.select_one(".k-price-tag__price")
        if not price_el:
            continue
        title = " ".join(
            x.get_text(" ", strip=True) for x in (title_el, subtitle_el) if x and x.get_text(strip=True)
        ).strip()
        if not title:
            continue
        iid = match_ingredient(title, ingredients)
        if not iid:
            continue
        price_txt = price_el.get_text(strip=True).replace(",", ".")
        try:
            price = float(re.sub(r"[^\d.]", "", price_txt))
        except ValueError:
            continue
        unit_txt = _clean_unit_price_text(unit_el.get_text(" ", strip=True)) if unit_el else ""
        ing_unit = ingredients[iid]["unit"]
        pk = parse_pack_size(unit_txt, ing_unit)
        if pk is None or pk <= 0:
            continue
        candidates.append({
            "iid": iid,
            "product": title,
            "price": price,
            "pk": pk,
            "label": unit_txt or None,
        })

    items = build_items(candidates)
    status = "ok" if len(items) >= 8 else ("teilweise" if items else "fehlt")
    return result(
        name=NAME,
        validFrom=valid_from,
        validTo=valid_to,
        status=status,
        source=SOURCE,
        items=items,
    )
