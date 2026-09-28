# Wocheneinkauf – Angebote

Automatischer Scraper für Supermarkt-Angebote in Münster (PLZ 48145), für den
[Wochenkorb-Planer](https://claude.ai/artifact/XE4FbSiUMGNRwot2GxUTCf). Läuft
jeden Sonntag um ca. 06:00 Uhr per GitHub Action, ganz ohne LLM oder API-Keys
– nur stdlib, `requests` und `beautifulsoup4`.

## Was hier passiert

1. `scraper/main.py` ruft nacheinander die Angebotsseiten von Aldi Nord,
   Lidl, Penny, Netto, Kaufland, Rewe und Edeka ab (`scraper/stores/*.py`).
2. Jeder gefundene Produkttitel wird über `scraper/matcher.py` mit den
   Zutaten aus `scraper/ingredients.json` abgeglichen (Schlüsselwörter +
   Ausschlusswörter, z. B. "butter" passt nicht auf "Butterkeks").
3. Packungsgrößen ("500 g", "2 x 250 g", "1 l", "5 Stück", …) werden in die
   Einheit der Zutat umgerechnet (`pk`). Nicht umrechenbare Angebote werden
   verworfen. Gibt es mehrere Treffer für eine Zutat in einem Markt, gewinnt
   der günstigste Preis pro Grundeinheit.
4. Das Ergebnis wird nach `angebote/AKTUELL.json` und `angebote/YYYY-KWnn.json`
   geschrieben (ISO-Kalenderwoche), alte `KWnn`-Dateien werden gelöscht.
   `angebote/log.txt` enthält eine Kurzzusammenfassung pro Markt.
5. Ein Markt, der nicht ausgelesen werden kann, bekommt `status: "fehlt"`
   mit leeren `items` – die App nutzt für ihn dann ihre Schätzpreise. Ein
   einzelner fehlgeschlagener Markt bricht den Lauf nie ab.

## Datenformat

Siehe `angebote/AKTUELL.json`:

```json
{
  "kw": "2026-KW40",
  "stand": "2026-09-28",
  "ort": "Münster (48145)",
  "hinweis": "...",
  "stores": {
    "aldi": {
      "name": "Aldi Nord",
      "validFrom": "2026-09-27", "validTo": "2026-10-03",
      "status": "ok",
      "source": "https://www.aldi-nord.de/angebote.html",
      "items": {
        "butter": {"product": "KERRYGOLD Butter", "price": 1.59, "pk": 250, "label": "250-g-Packung"}
      }
    }
  }
}
```

`pk` ist die Packungsgröße in der Einheit der Zutat (`g`, `ml`, `Stk`, `Zehe`,
`Bund`) – so wie im Planer definiert (`web/wochenkorb.html`, `const ING`).

## Marktabdeckung (Stand: erster Testlauf)

| Markt    | Status | Warum |
|----------|--------|-------|
| Aldi Nord | funktioniert gut | Next.js-Seite liefert den kompletten Wochen-Katalog serverseitig als eingebettetes JSON (`__NEXT_DATA__` → `apiData` → `OFFER_GET`). |
| Kaufland | funktioniert gut | `filiale.kaufland.de/angebote/uebersicht.html` ist serverseitig gerendertes HTML mit allen Produktkacheln. |
| Lidl | fehlt | Angebote nur als Bildprospekt (Online-Flyer), kein auslesbarer Text. |
| Penny | fehlt | HTML-Grundgerüst wird geladen, die eigentlichen Angebotskacheln bleiben leere Platzhalter und werden erst per JavaScript befüllt. |
| Netto | fehlt | `netto-online.de` blockiert automatische Zugriffe (HTTP 403). |
| Rewe | fehlt | `rewe.de` blockiert automatische Zugriffe (HTTP 403). |
| Edeka | fehlt | `edeka.de` blockiert automatische Zugriffe (HTTP 403); der Hafenmarkt-Prospekt existiert zusätzlich nur als Bild. |

Die GitHub-Runner-IPs können von den Shops anders behandelt werden als ein
lokaler Rechner (andere Reputationslisten, evtl. zusätzliche Rate-Limits) –
`status: "ok"` bei Aldi/Kaufland auf dem Mac ist also keine Garantie, dass es
auf dem Runner genauso läuft. Der Workflow committet trotzdem immer die
aktuellen Ergebnisse, auch wenn einzelne (oder alle) Märkte gerade "fehlt"
melden.

## Manuell ausführen

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 -m scraper.main
```

## Zutatenkatalog aktualisieren

`scraper/ingredients.json` wird aus `scraper/build_ingredients.py` erzeugt.
Ändert sich `const ING` in `web/wochenkorb.html` (neue Zutat, neue Packung),
`build_ingredients.py` entsprechend anpassen (inkl. Such-/Ausschluss-Wörter)
und neu erzeugen:

```bash
python3 scraper/build_ingredients.py
```

## GitHub Action

`.github/workflows/angebote.yml`: läuft jeden Sonntag um 06:00 Uhr
Europe/Berlin (`cron: "0 4 * * 0"`, UTC) sowie manuell über
"Run workflow". Committet und pusht Änderungen in `angebote/` mit der
github-actions-Bot-Identität. Bricht nicht ab, wenn sich nichts geändert hat.
