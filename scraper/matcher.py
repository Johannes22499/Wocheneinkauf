"""
Common offer-text -> ingredient matching and pack-size parsing.

No LLM, no external services - pure string/regex heuristics tuned by hand
in ingredients.json (match / exclude keyword lists per ingredient).
"""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import Optional

HERE = os.path.dirname(os.path.abspath(__file__))

_UMLAUT_MAP = str.maketrans({
    "ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss",
    "Ä": "Ae", "Ö": "Oe", "Ü": "Ue",
})


def _fold(s: str) -> str:
    """lowercase, keep umlauts as-is (German offer texts use them consistently)."""
    return s.lower().strip()


def load_ingredients() -> dict:
    with open(os.path.join(HERE, "ingredients.json"), encoding="utf-8") as f:
        return json.load(f)


def _word_boundary_hit(keyword: str, text: str) -> bool:
    """True if keyword occurs in text as a whole word/phrase (case-insensitive)."""
    pattern = r"(?<![a-zäöüß0-9])" + re.escape(keyword) + r"(?![a-zäöüß0-9])"
    return re.search(pattern, text, flags=re.IGNORECASE) is not None


def match_ingredient(title: str, ingredients: dict) -> Optional[str]:
    """
    Return the ingredient id whose keywords best match `title`, or None.
    Longest matching keyword wins if several ingredients would match
    (e.g. 'süßkartoffel' before 'kartoffeln').
    """
    text = _fold(title)
    best_id = None
    best_len = -1
    for iid, ing in ingredients.items():
        excluded = any(_word_boundary_hit(_fold(x), text) for x in ing.get("exclude", []))
        if excluded:
            continue
        for kw in ing.get("match", []):
            kwf = _fold(kw)
            if _word_boundary_hit(kwf, text):
                if len(kwf) > best_len:
                    best_len = len(kwf)
                    best_id = iid
    return best_id


# ---------------------------------------------------------------------------
# Pack size parsing: "500 g", "2 x 250 g", "1 l", "6 Stk", "1 kg", "3 Stück" ...
# ---------------------------------------------------------------------------

_NUM = r"(\d+(?:[.,]\d+)?)"

_SEP = r"[\s-]*"

_PATTERNS = [
    # multipack: "2 x 250 g" / "2x250g" / "4 x 150 g"
    (re.compile(rf"{_NUM}{_SEP}x{_SEP}{_NUM}{_SEP}(kg|g|ml|l)\b", re.IGNORECASE), "multipack"),
    # single: "500 g" / "150-g-Becher" / "1L" / "5-kg-Netz"
    (re.compile(rf"{_NUM}{_SEP}(kg|g|ml|l)\b", re.IGNORECASE), "single"),
    (re.compile(rf"{_NUM}{_SEP}(st(?:ü|u)ck|stk)\b", re.IGNORECASE), "stk"),
]

_UNIT_FACTOR = {"kg": 1000.0, "g": 1.0, "l": 1000.0, "ml": 1.0}


@dataclass
class ParsedPack:
    quantity: float   # in the ingredient's target unit, if convertible
    raw_unit: str      # g/ml/Stk (source-normalised)


def parse_pack_size(text: str, ingredient_unit: str) -> Optional[float]:
    """
    Try to find a pack size in `text` and convert it to `ingredient_unit`
    (g|ml|Stk|Zehe|Bund). Returns None if not parseable / not convertible.
    """
    t = text.replace(",", ".")

    m = _PATTERNS[0][0].search(t)  # multipack "n x m unit"
    if m:
        n = float(m.group(1))
        size = float(m.group(2))
        unit = m.group(3).lower()
        total = n * size
        if unit in ("kg", "g") and ingredient_unit == "g":
            return total * _UNIT_FACTOR[unit]
        if unit in ("l", "ml") and ingredient_unit == "ml":
            return total * _UNIT_FACTOR[unit]
        return None

    m = _PATTERNS[1][0].search(t)  # single "n unit"
    if m:
        n = float(m.group(1))
        unit = m.group(2).lower()
        if unit in ("kg", "g") and ingredient_unit == "g":
            return n * _UNIT_FACTOR[unit]
        if unit in ("l", "ml") and ingredient_unit == "ml":
            return n * _UNIT_FACTOR[unit]
        return None

    m = _PATTERNS[2][0].search(t)  # "n Stück" / "n Stk"
    if m and ingredient_unit == "Stk":
        return float(m.group(1))

    # bare "Stück"/"Stk" with implicit count 1 (e.g. "Gurke", "Salatgurke")
    if ingredient_unit == "Stk" and re.search(r"\bst(?:ü|u)ck\b", t, re.IGNORECASE):
        return 1.0

    return None


def price_per_base_unit(price: float, pk: float) -> float:
    """Price per gram/ml/Stück - used to pick the cheapest offer per ingredient."""
    if pk <= 0:
        return float("inf")
    return price / pk
