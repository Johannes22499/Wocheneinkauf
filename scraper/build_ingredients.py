#!/usr/bin/env python3
"""
Builds scraper/ingredients.json from the ING catalogue that is hand-curated below
(extracted once from web/wochenkorb.html, `const ING`, line ~254).

Run manually whenever the ingredient catalogue in wochenkorb.html changes:
    python3 scraper/build_ingredients.py

The GitHub Action does NOT run this script - it only reads the checked-in
scraper/ingredients.json. This keeps the weekly scrape independent of the
(private, local-only) Downloads/Tete project.
"""
import json
import os

# id: [Name, unit, packSize, basePrice, category, tags, packName?]
ING = {
    "spaghetti": ["Spaghetti", "g", 500, .99, "trocken", "glut"],
    "penne": ["Penne", "g", 500, .99, "trocken", "glut"],
    "reis": ["Langkornreis", "g", 1000, 1.79, "trocken", ""],
    "couscous": ["Couscous", "g", 500, 1.49, "trocken", "glut"],
    "linsen": ["Rote Linsen", "g", 500, 1.69, "trocken", "hist"],
    "lasagne": ["Lasagneplatten", "g", 500, 1.19, "trocken", "glut"],
    "wraps": ["Weizen-Wraps", "Stk", 6, 1.29, "trocken", "glut", "6 Stk"],
    "gnocchi": ["Gnocchi", "g", 500, 1.29, "kuehl", "glut"],
    "kartoffeln": ["Kartoffeln, festkochend", "g", 2000, 2.49, "obst", ""],
    "suesskart": ["Süßkartoffeln", "g", 1000, 2.99, "obst", ""],
    "zwiebeln": ["Zwiebeln", "g", 1000, 1.29, "obst", ""],
    "knoblauch": ["Knoblauch", "Zehe", 30, .99, "obst", "", "3 Knollen"],
    "karotten": ["Karotten", "g", 1000, 1.19, "obst", ""],
    "zucchini": ["Zucchini", "Stk", 1, .79, "obst", ""],
    "paprika": ["Paprika rot", "Stk", 3, 1.99, "obst", "", "3 Stk"],
    "brokkoli": ["Brokkoli", "Stk", 1, 1.49, "obst", ""],
    "blumenkohl": ["Blumenkohl", "Stk", 1, 1.99, "obst", ""],
    "kuerbis": ["Hokkaido-Kürbis", "Stk", 1, 1.99, "obst", ""],
    "lauch": ["Lauch", "Stk", 1, .89, "obst", ""],
    "gurke": ["Salatgurke", "Stk", 1, .69, "obst", ""],
    "salat": ["Eisbergsalat", "Stk", 1, .99, "obst", ""],
    "champignons": ["Champignons", "g", 250, 1.49, "obst", ""],
    "fzwiebel": ["Frühlingszwiebeln", "Bund", 1, .69, "obst", ""],
    "avocado": ["Avocado", "Stk", 1, .99, "obst", "hist"],
    "tomdose": ["Tomaten, gehackt", "g", 400, .65, "konserve", "hist", "Dose 400 g"],
    "tommark": ["Tomatenmark", "g", 200, .79, "konserve", "hist"],
    "kicher": ["Kichererbsen", "g", 400, .89, "konserve", "hist", "Dose 400 g"],
    "kidney": ["Kidneybohnen", "g", 400, .79, "konserve", "hist", "Dose 400 g"],
    "mais": ["Mais", "g", 285, .89, "konserve", "", "Dose 285 g"],
    "kokos": ["Kokosmilch", "ml", 400, 1.29, "konserve", "", "Dose 400 ml"],
    "thunfisch": ["Thunfisch im eigenen Saft", "g", 150, 1.49, "konserve", "fisch hist", "Dose 150 g"],
    "soja": ["Sojasauce", "ml", 150, 1.49, "konserve", "hist"],
    "sahne": ["Schlagsahne", "ml", 200, .79, "kuehl", "milch lakt"],
    "milch": ["Milch 1,5 %", "ml", 1000, 1.09, "kuehl", "milch lakt"],
    "butter": ["Butter", "g", 250, 2.29, "kuehl", "milch"],
    "eier": ["Eier, Freilandhaltung", "Stk", 10, 2.99, "kuehl", "ei", "10 Stk"],
    "mozzarella": ["Mozzarella", "g", 125, .89, "kuehl", "milch lakt"],
    "parmesan": ["Grana Padano, gerieben", "g", 100, 1.79, "kuehl", "milch hist"],
    "gouda": ["Gouda, gerieben", "g", 200, 1.79, "kuehl", "milch hist"],
    "feta": ["Feta", "g", 200, 1.49, "kuehl", "milch lakt hist"],
    "frischkaese": ["Frischkäse", "g", 200, .99, "kuehl", "milch lakt"],
    "quark": ["Speisequark", "g", 500, 1.29, "kuehl", "milch lakt"],
    "tofu": ["Tofu natur", "g", 400, 1.99, "kuehl", "hist"],
    "haehnchen": ["Hähnchenbrustfilet", "g", 400, 4.49, "fleisch", "fleisch"],
    "pute": ["Putenschnitzel", "g", 400, 4.79, "fleisch", "fleisch"],
    "rinderhack": ["Rinderhackfleisch", "g", 500, 5.49, "fleisch", "fleisch hist"],
    "hack": ["Hackfleisch, gemischt", "g", 500, 3.99, "fleisch", "fleisch hist"],
    "schwein": ["Schweineschnitzel", "g", 500, 4.99, "fleisch", "fleisch"],
    "speck": ["Speckwürfel", "g", 125, 1.29, "fleisch", "fleisch hist"],
    "lachs": ["Lachsfilet, tiefgekühlt", "g", 250, 3.99, "tk", "fisch"],
    "spinat": ["Blattspinat, tiefgekühlt", "g", 450, 1.29, "tk", "hist"],
    "erbsen": ["Erbsen, tiefgekühlt", "g", 1000, 1.99, "tk", ""],
    "oel": ["Rapsöl", "ml", 1000, 2.29, "vorrat", "basic"],
    "bruehe": ["Gemüsebrühe, Pulver", "g", 250, 1.29, "vorrat", "basic"],
    "mehl": ["Weizenmehl", "g", 1000, .69, "vorrat", "basic glut"],
}

# Hand-curated German matching keywords per ingredient id.
# match: any of these (word-boundary, case-insensitive) found in offer title -> candidate match.
# exclude: if any of these appear in the offer title -> reject, even if a match keyword hit.
KEYWORDS = {
    "spaghetti": {"match": ["spaghetti"], "exclude": ["eis", "haribo", "balla-stixx", "balla stixx", "lakritz",
                                                        "tomatensauce", "fertiggericht", "dose", "sauce", "soße", "glas"]},
    "penne": {"match": ["penne", "rigate"], "exclude": ["tomatensauce", "fertiggericht", "dose", "sauce", "soße", "glas"]},
    "reis": {"match": ["reis", "basmati", "langkornreis", "jasminreis", "risotto"],
             "exclude": ["milchreis", "reiswaffel", "reisflocken", "reiscracker", "reisdrink", "reisgetränk",
                         "reisbrei", "reisnudeln", "reis-nudeln"]},
    "couscous": {"match": ["couscous"], "exclude": []},
    "linsen": {"match": ["linsen"], "exclude": ["linsensuppe", "linsenchips", "linsennudel"]},
    "lasagne": {"match": ["lasagneplatten", "lasagne blätter", "lasagneblätter"],
                "exclude": ["lasagne bolognese", "fertiglasagne", "tiefkühllasagne"]},
    "wraps": {"match": ["wraps", "tortilla", "tortillas"], "exclude": ["wrapfolie", "tortilla-chips", "tortillachips", "chips"]},
    "gnocchi": {"match": ["gnocchi"], "exclude": []},
    "kartoffeln": {"match": ["kartoffeln", "speisekartoffeln", "kartoffel"],
                   "exclude": ["kartoffelchips", "kartoffelsalat", "kartoffelpüree", "kartoffelknödel",
                               "kartoffelsuppe", "kartoffelecken", "kartoffelpuffer", "süßkartoffel", "süßkartoffeln"]},
    "suesskart": {"match": ["süßkartoffel", "süßkartoffeln", "batate", "bataten"], "exclude": ["süßkartoffelchips", "süßkartoffelpommes"]},
    "zwiebeln": {"match": ["zwiebeln", "zwiebel"],
                 "exclude": ["frühlingszwiebel", "frühlingszwiebeln", "zwiebelmettwurst", "zwiebelringe",
                             "zwiebelsuppe", "zwiebelmarmelade", "röstzwiebel", "zwiebelbrot", "lauchzwiebel"]},
    "knoblauch": {"match": ["knoblauch"], "exclude": ["knoblauchbrot", "knoblauchbaguette", "knoblauchbutter",
                                                        "knoblauchsauce", "knoblauchsoße", "knoblauchdip", "knoblauchsalz"]},
    "karotten": {"match": ["karotten", "möhren", "möhre"], "exclude": ["karottensaft", "möhrensaft", "karottensalat"]},
    "zucchini": {"match": ["zucchini"], "exclude": ["zucchinichips"]},
    "paprika": {"match": ["paprika"], "exclude": ["paprikachips", "paprikapulver", "paprikagewürz", "paprikasalami",
                                                    "paprikacreme", "paprikasauce"]},
    "brokkoli": {"match": ["brokkoli", "broccoli"], "exclude": []},
    "blumenkohl": {"match": ["blumenkohl"], "exclude": ["blumenkohlreis"]},
    "kuerbis": {"match": ["hokkaido", "kürbis"], "exclude": ["kürbiskern", "kürbiskernöl", "kürbissuppe", "kürbisbrot"]},
    "lauch": {"match": ["lauch", "porree"], "exclude": ["frühlingszwiebel", "lauchzwiebel", "lauchgemüse tk"]},
    "gurke": {"match": ["gurke", "salatgurke", "schlangengurke"], "exclude": ["gurkensalat", "gewürzgurke", "gewürzgurken",
                                                                              "senfgurken", "cornichons", "gurkenglas"]},
    "salat": {"match": ["eisbergsalat", "kopfsalat"], "exclude": ["salatsauce", "salatdressing", "kartoffelsalat",
                                                                   "nudelsalat", "fruchtsalat", "salatgurke"]},
    "champignons": {"match": ["champignons", "champignon"], "exclude": ["champignonsuppe", "champignoncreme",
                                                                        "schlemmerfilet", "käserei champignon", "kaeserei champignon"]},
    "fzwiebel": {"match": ["frühlingszwiebel", "frühlingszwiebeln"], "exclude": []},
    "avocado": {"match": ["avocado", "avocados"], "exclude": ["avocadoöl", "avocadocreme", "guacamole"]},
    "tomdose": {"match": ["tomaten", "gehackte tomaten", "stückige tomaten"],
                "exclude": ["tomatensaft", "tomatenmark", "tomatensoße", "tomatensauce", "tomatenketchup",
                            "cherrytomaten", "kirschtomaten", "tomatenchips", "getrocknete tomaten",
                            "rahmsauce", "sauce", "soße", "suppe", "chutney"]},
    "tommark": {"match": ["tomatenmark"], "exclude": []},
    "kicher": {"match": ["kichererbsen"], "exclude": ["kichererbsenchips", "kichererbsennudeln"]},
    "kidney": {"match": ["kidneybohnen"], "exclude": []},
    "mais": {"match": ["mais", "zuckermais"], "exclude": ["maiskeimöl", "maiswaffel", "maischips", "maisstärke",
                                                             "popcorn", "cornflakes", "maisbrot",
                                                             "mais-hähnchen", "maishähnchen", "hähnchen-schenkel",
                                                             "hähnchenschenkel", "schenkel"]},
    "kokos": {"match": ["kokosmilch"], "exclude": ["kokosmilchjoghurt", "kokosmilchdessert", "milchreis",
                                                    "grießpudding", "pudding", "dessert"]},
    "thunfisch": {"match": ["thunfisch"], "exclude": ["thunfischsalat", "salat"]},
    "soja": {"match": ["sojasauce", "sojasoße"], "exclude": ["sojamilch", "sojadrink", "sojajoghurt", "sojaöl"]},
    "sahne": {"match": ["schlagsahne", "sahne"], "exclude": ["saure sahne", "sahnejoghurt", "sahnesoße", "sahnesauce",
                                                              "kokossahne", "sahnequark", "sahnesteif",
                                                              "sahne-toffee", "sahne-toffees", "sahnetoffee", "toffee"]},
    "milch": {"match": ["h-milch", "frischmilch", "vollmilch", "fettarme milch"],
              "exclude": ["kondensmilch", "kokosmilch", "buttermilch", "sojamilch", "hafermilch", "mandelmilch",
                          "milchreis", "milchschnitte", "milchshake", "kaffeemilch", "ziegenmilch"]},
    "butter": {"match": ["butter"], "exclude": ["butterkeks", "butterkekse", "buttermilch", "erdnussbutter",
                                                  "butterbrot", "butterkäse", "buttergebäck", "butteraroma",
                                                  "butterschmalz", "kräuterbutter", "nut-butter", "nussbutter",
                                                  "butter-cups", "buttercups", "cashewbutter", "mandelbutter"]},
    "eier": {"match": ["eier", "freilandeier"], "exclude": ["eierlikör", "eiernudeln", "rühreigewürz", "ostereier",
                                                             "nudeln", "teigware", "teigwaren", "mie-nudeln",
                                                             "wok-nudeln", "eier-mie-nudeln", "eier-wok-nudeln"]},
    "mozzarella": {"match": ["mozzarella"], "exclude": []},
    "parmesan": {"match": ["parmesan", "grana padano"], "exclude": []},
    "gouda": {"match": ["gouda"], "exclude": []},
    "feta": {"match": ["feta"], "exclude": ["fetacreme", "fetadip"]},
    "frischkaese": {"match": ["frischkäse"], "exclude": ["frischkäsezubereitung mit"]},
    "quark": {"match": ["speisequark", "quark"], "exclude": ["quarkbällchen", "quarktasche", "quarkkeulchen",
                                                              "kräuterquark fertig", "genuss", "dessert",
                                                              "früchtequark", "fruchtquark"]},
    "tofu": {"match": ["tofu"], "exclude": []},
    "haehnchen": {"match": ["hähnchenbrustfilet", "hähnchenbrust", "hähnchen-innenfilet", "hähnchenfilet"],
                  "exclude": ["hähnchenschenkel", "hähnchennuggets", "hähnchenwurst", "geflügelwurst"]},
    "pute": {"match": ["putenschnitzel", "putenbrust", "putenbrustfilet"], "exclude": ["putenaufschnitt", "putenwurst"]},
    "rinderhack": {"match": ["rinderhack", "rinderhackfleisch"], "exclude": ["rinderhack-spieße"]},
    "hack": {"match": ["hackfleisch gemischt", "gemischtes hackfleisch", "hackfleisch"],
             "exclude": ["rinderhack", "rinderhackfleisch", "hackbraten", "hacksteak", "hackfleischsauce",
                         "hähnchen-hackfleisch", "hähnchenhackfleisch", "geflügelhack", "putenhack", "hähnchenhack"]},
    "schwein": {"match": ["schweineschnitzel", "schweinerückensteak"], "exclude": ["schweinebraten", "schweinewurst"]},
    "speck": {"match": ["speckwürfel"], "exclude": ["speckstein", "frühstücksspeck"]},
    "lachs": {"match": ["lachsfilet"], "exclude": ["räucherlachs", "lachsschinken", "graved lachs", "lachs im brotteig",
                                                     "lachsstäbchen", "lachs sushi"]},
    "spinat": {"match": ["blattspinat", "spinat"], "exclude": ["spinatknödel", "spinat-ricotta", "spinatnudeln",
                                                                "spinat lasagne", "rahmspinat"]},
    "erbsen": {"match": ["erbsen"], "exclude": ["erbsensuppe", "erbseneintopf", "erbsenchips"]},
    "oel": {"match": ["rapsöl"], "exclude": ["rapsölmargarine"]},
    "bruehe": {"match": ["gemüsebrühe"], "exclude": ["gemüsebrühwürfel fertig"]},
    "mehl": {"match": ["weizenmehl", "mehl type 405", "mehl 405"], "exclude": ["maismehl", "mandelmehl", "kokosmehl",
                                                                                  "vollkornmehl dinkel", "buchweizenmehl"]},
}

def main():
    out = {}
    for iid, arr in ING.items():
        name, unit, pack, price, category, tags = arr[0], arr[1], arr[2], arr[3], arr[4], arr[5]
        pack_name = arr[6] if len(arr) > 6 else None
        kw = KEYWORDS.get(iid, {"match": [name.lower()], "exclude": []})
        out[iid] = {
            "name": name,
            "unit": unit,
            "pack": pack,
            "basePrice": price,
            "category": category,
            "tags": [t for t in tags.split(" ") if t],
            "packName": pack_name,
            "match": kw["match"],
            "exclude": kw["exclude"],
        }
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "ingredients.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print(f"wrote {len(out)} ingredients")

if __name__ == "__main__":
    main()
