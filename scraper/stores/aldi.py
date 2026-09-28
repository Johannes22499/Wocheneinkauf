"""
Aldi Nord (Münster = Aldi Nord region).

The public offers page (https://www.aldi-nord.de/angebote.html) is a
Next.js app; the full current week's offer catalogue is embedded server-side
in <script id="__NEXT_DATA__"> as a JSON-encoded string at
props.pageProps.apiData -> [["OFFER_GET", {"res": {"algoliaDataMap": {...}}}], ...].
No public REST endpoint needs to be called separately - everything needed is
in the first HTML response. weekSwitchPer == "Sunday", i.e. this "current"
week already is the week that starts on the Sunday the scraper runs.

Manual testing note: aldi-nord.de intermittently times out on the very first
TLS handshake from some networks; a short retry loop is used.
"""
from __future__ import annotations

import datetime
import json
import re

from scraper.webclient import new_session
from scraper.matcher import load_ingredients, match_ingredient
from scraper.stores.common import build_items, failed, result

NAME = "Aldi Nord"
SOURCE = "https://www.aldi-nord.de/angebote.html"

_SALES_UNIT_RE = re.compile(
    r"(?P<mult>\d+)\s*x\s*(?P<size>\d+(?:[.,]\d+)?)\s*-?\s*(?P<unit>kg|g|ml|l)\b|"
    r"(?P<size2>\d+(?:[.,]\d+)?)\s*-\s*(?P<unit2>kg|g|ml|l)\b",
    re.IGNORECASE,
)

_UNIT_FACTOR = {"kg": 1000.0, "g": 1.0, "l": 1000.0, "ml": 1.0}


def _parse_sales_unit(sales_unit: str, ingredient_unit: str):
    if not sales_unit:
        return None
    s = sales_unit.replace(",", ".")
    m = _SALES_UNIT_RE.search(s)
    if m:
        if m.group("mult"):
            total = float(m.group("mult")) * float(m.group("size"))
            unit = m.group("unit").lower()
        else:
            total = float(m.group("size2"))
            unit = m.group("unit2").lower()
        if unit in ("kg", "g") and ingredient_unit == "g":
            return total * _UNIT_FACTOR[unit]
        if unit in ("l", "ml") and ingredient_unit == "ml":
            return total * _UNIT_FACTOR[unit]
        return None
    if ingredient_unit == "Stk" and re.search(r"st(?:ü|u)ck", s, re.IGNORECASE):
        return 1.0
    if ingredient_unit == "Bund" and "bund" in s.lower():
        return 1.0
    return None


def _fetch_apidata(session, attempts=3):
    last_err = None
    for _ in range(attempts):
        try:
            resp = session.get(SOURCE, timeout=30)
            resp.raise_for_status()
            html = resp.text
            m = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
            if not m:
                raise ValueError("__NEXT_DATA__ not found")
            data = json.loads(m.group(1))
            api_data_raw = data["props"]["pageProps"]["apiData"]
            api_data = json.loads(api_data_raw)
            for key, payload in api_data:
                if key == "OFFER_GET":
                    return payload["res"]
            raise ValueError("OFFER_GET not present in apiData")
        except Exception as e:  # noqa: BLE001
            last_err = e
    raise last_err


def scrape():
    session = new_session()
    ingredients = load_ingredients()

    try:
        res = _fetch_apidata(session)
    except Exception as e:  # noqa: BLE001
        return failed(NAME, SOURCE, None, None, reason=f"Abruf fehlgeschlagen: {e}")

    amap = res.get("algoliaDataMap", {})
    if not amap:
        return failed(NAME, SOURCE, None, None, reason="Keine Angebotsdaten im __NEXT_DATA__ gefunden")

    valid_from = valid_to = None
    candidates = []
    for _id, item in amap.items():
        brand = (item.get("brandName") or "").strip()
        pname = (item.get("name") or "").strip()
        title = (brand + " " + pname).strip()
        if not title:
            continue
        iid = match_ingredient(title, ingredients)
        if not iid:
            continue
        cp = item.get("currentPrice") or {}
        price = cp.get("priceValue")
        if price is None:
            continue
        sales_unit = item.get("salesUnit") or ""
        ing_unit = ingredients[iid]["unit"]
        pk = _parse_sales_unit(sales_unit, ing_unit)
        if pk is None or pk <= 0:
            continue
        vf = cp.get("validFrom")
        vt = cp.get("validUntil")
        if vf and (valid_from is None or vf < valid_from):
            valid_from = vf
        if vt and (valid_to is None or vt > valid_to):
            valid_to = vt
        candidates.append({
            "iid": iid,
            "product": title,
            "price": float(price),
            "pk": pk,
            "label": sales_unit,
        })

    items = build_items(candidates)

    def fmt(ts):
        if not ts:
            return None
        return datetime.datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d")

    status = "ok" if len(items) >= 8 else ("teilweise" if items else "fehlt")
    return result(
        name=NAME,
        validFrom=fmt(valid_from),
        validTo=fmt(valid_to),
        status=status,
        source=SOURCE,
        items=items,
    )
