"""Shared helpers for building a per-store result and picking cheapest offers."""
from __future__ import annotations

from scraper.matcher import price_per_base_unit


def build_items(candidates: list[dict]) -> dict:
    """
    candidates: list of {iid, product, price, pk, label, note?, app?}
    When several offers match the same ingredient, keep the cheapest per
    base unit (price / pk).
    """
    best: dict[str, dict] = {}
    for c in candidates:
        iid = c["iid"]
        if iid not in best or price_per_base_unit(c["price"], c["pk"]) < price_per_base_unit(
            best[iid]["price"], best[iid]["pk"]
        ):
            best[iid] = c
    items = {}
    for iid, c in best.items():
        entry = {"product": c["product"], "price": round(c["price"], 2), "pk": c["pk"], "label": c["label"]}
        if c.get("note"):
            entry["note"] = c["note"]
        if c.get("app"):
            entry["app"] = True
        items[iid] = entry
    return items


def result(*, name, validFrom, validTo, status, source, items, market=None):
    out = {
        "name": name,
        "validFrom": validFrom,
        "validTo": validTo,
        "status": status,
        "source": source,
        "items": items,
    }
    if market:
        out["market"] = market
    return out


def failed(name, source, validFrom, validTo, reason=""):
    return {
        "name": name,
        "validFrom": validFrom,
        "validTo": validTo,
        "status": "fehlt",
        "source": source,
        "items": {},
        **({"note": reason} if reason else {}),
    }
