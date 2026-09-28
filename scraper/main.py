#!/usr/bin/env python3
"""
Weekly offer scraper for the Wochenkorb meal planner (Münster, PLZ 48145).

Runs every Sunday via GitHub Actions (see .github/workflows/angebote.yml).
No LLM, no API keys - stdlib + requests + BeautifulSoup only.

Writes:
  angebote/AKTUELL.json
  angebote/YYYY-KWnn.json   (ISO week of the run)
  angebote/log.txt
and deletes older angebote/*-KW*.json files.

A single store failing (network error, site blocks us, page structure
changed, ...) never aborts the whole run - it just gets status "fehlt"
with an empty item list, and the app then falls back to estimated prices
for that store.
"""
from __future__ import annotations

import datetime
import glob
import json
import os
import sys
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(HERE)
sys.path.insert(0, REPO_ROOT)

from scraper.stores import aldi, kaufland, lidl, netto, penny, rewe, edeka  # noqa: E402

# Store key order matches the app's market keys in web/wochenkorb.html.
STORE_MODULES = {
    "aldi": aldi,
    "lidl": lidl,
    "penny": penny,
    "netto": netto,
    "kaufland": kaufland,
    "rewe": rewe,
    "edeka": edeka,
}

ORT = "Münster (48145)"


def iso_week_label(d: datetime.date) -> str:
    iso = d.isocalendar()
    return f"{iso[0]}-KW{iso[1]:02d}"


def run_store(key, module, log_lines):
    try:
        r = module.scrape()
    except Exception as e:  # noqa: BLE001
        traceback.print_exc()
        r = {
            "name": getattr(module, "NAME", key),
            "validFrom": None,
            "validTo": None,
            "status": "fehlt",
            "source": getattr(module, "SOURCE", ""),
            "items": {},
            "note": f"Unerwarteter Fehler: {e}",
        }
    n_items = len(r.get("items", {}))
    log_lines.append(f"{key:10} status={r['status']:12} items={n_items:3}  source={r.get('source','')}")
    return r


def main():
    today = datetime.date.today()
    stand = today.isoformat()
    kw = iso_week_label(today)

    log_lines = [f"Angebote-Scrape {stand} ({kw})", ""]

    # Monday..Saturday of the coming week (if run on Sunday) / current week otherwise.
    monday = today - datetime.timedelta(days=today.weekday())
    if today.weekday() == 6:  # Sunday -> next Monday starts the new week
        monday = today + datetime.timedelta(days=1)
    saturday = monday + datetime.timedelta(days=5)

    stores = {}
    for key, module in STORE_MODULES.items():
        s = run_store(key, module, log_lines)
        if s.get("validFrom") is None:
            s["validFrom"] = monday.isoformat()
        if s.get("validTo") is None:
            s["validTo"] = saturday.isoformat()
        stores[key] = s

    matched_total = sum(len(s["items"]) for s in stores.values())
    ok_stores = [k for k, s in stores.items() if s["status"] == "ok"]
    teilweise_stores = [k for k, s in stores.items() if s["status"] == "teilweise"]
    fehlt_stores = [k for k, s in stores.items() if s["status"] == "fehlt"]

    log_lines.append("")
    log_lines.append(f"ok: {', '.join(ok_stores) or '-'}")
    log_lines.append(f"teilweise: {', '.join(teilweise_stores) or '-'}")
    log_lines.append(f"fehlt: {', '.join(fehlt_stores) or '-'}")
    log_lines.append(f"gesamt gematchte Artikel: {matched_total}")

    hinweis = (
        "pk = Packungsgröße in der Einheit der Zutat aus dem Planer (g, ml, Stk, Zehe, Bund). "
        "Nur Angebote, die zu Planer-Zutaten passen. Automatisch erzeugt (scraper/main.py), "
        f"ohne LLM. Fehlende Märkte ({', '.join(fehlt_stores) or '-'}) nutzen Schätzpreise."
    )

    output = {
        "kw": kw,
        "stand": stand,
        "ort": ORT,
        "hinweis": hinweis,
        "stores": stores,
    }

    angebote_dir = os.path.join(REPO_ROOT, "angebote")
    os.makedirs(angebote_dir, exist_ok=True)

    # delete older week files
    for path in glob.glob(os.path.join(angebote_dir, "*-KW*.json")):
        try:
            os.remove(path)
        except OSError:
            pass

    kw_path = os.path.join(angebote_dir, f"{kw}.json")
    aktuell_path = os.path.join(angebote_dir, "AKTUELL.json")
    with open(kw_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    with open(aktuell_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    log_path = os.path.join(angebote_dir, "log.txt")
    with open(log_path, "w", encoding="utf-8") as f:
        f.write("\n".join(log_lines) + "\n")

    print("\n".join(log_lines))
    print(f"\nGeschrieben: {kw_path}")
    print(f"Geschrieben: {aktuell_path}")


if __name__ == "__main__":
    main()
