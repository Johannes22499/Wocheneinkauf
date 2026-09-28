import Foundation
import Testing
@testable import Wochenkorb

@MainActor
enum TestFixtures {
    static let catalog = Catalog.loadBundled(bundle: Bundle(for: BundleToken.self))

    static func offers(validFrom: String, validTo: String) -> OffersFile {
        OffersFile(
            kw: "test", stand: validFrom, ort: nil, hinweis: nil,
            stores: [
                "aldi": StoreOffer(
                    name: "Aldi Nord", market: nil, validFrom: validFrom, validTo: validTo,
                    status: nil, source: nil,
                    items: ["milch": OfferItem(product: "Testmilch", price: 0.5, pk: 1000, label: "1 l", note: nil, app: nil)]
                )
            ]
        )
    }
}

private final class BundleToken {}

@Suite("Planner")
struct PlannerTests {

    @MainActor
    private func makePlanner(settings: Settings = Settings(), offers: OffersFile? = nil, today: String = "2026-09-28") -> Planner {
        Planner(catalog: TestFixtures.catalog, offers: offers, settings: settings, today: today)
    }

    // MARK: - packsFor rounding

    @MainActor
    @Test("packsFor rounds up whole packs, with a small epsilon for float noise")
    func packsForRounding() {
        let p = makePlanner()
        #expect(p.packsFor(500, 500) == 1)      // exactly one pack
        #expect(p.packsFor(501, 500) == 1)      // 501/500=1.002, -0.03=0.972 -> ceil=1: tiny overage is tolerated
        #expect(p.packsFor(520, 500) == 2)      // 520/500=1.04, -0.03=1.01 -> ceil=2
        #expect(p.packsFor(550, 500) == 2)      // 1.1-0.03=1.07 -> ceil=2
        #expect(p.packsFor(0, 500) == 1)        // max(1, ceil(-0.03)) = max(1,0) = 1
        #expect(p.packsFor(1000, 500) == 2)     // exactly two packs
        #expect(p.packsFor(1490, 500) == 3)     // 2.98-0.03=2.95 -> ceil=3
        #expect(p.packsFor(1, 30) == 1)         // Knoblauch: 1 Zehe of a 30-Zehe pack
    }

    // MARK: - Best-buy across two stores, incl. tie-break

    @MainActor
    @Test("bestBuy picks the cheaper store, and on a tie the one with less leftover")
    func bestBuyTwoStoreTieBreak() {
        var settings = Settings()
        settings.stores = ["aldi", "lidl"]
        settings.app = true
        // Force identical totals (0.99 € for 1 pack) but different pack sizes via offers,
        // so the tie-break (less leftover) decides.
        let offers = OffersFile(
            kw: "t", stand: "2026-09-28", ort: nil, hinweis: nil,
            stores: [
                "aldi": StoreOffer(name: nil, market: nil, validFrom: "2026-09-01", validTo: "2026-12-31", status: nil, source: nil,
                                    items: ["milch": OfferItem(product: "Milch A", price: 0.99, pk: 1000, label: "1 l", note: nil, app: nil)]),
                "lidl": StoreOffer(name: nil, market: nil, validFrom: "2026-09-01", validTo: "2026-12-31", status: nil, source: nil,
                                    items: ["milch": OfferItem(product: "Milch B", price: 0.99, pk: 500, label: "0.5 l", note: nil, app: nil)])
            ]
        )
        let p = makePlanner(settings: settings, offers: offers)
        // Need 400 ml: aldi needs 1 pack of 1000 (400 ml wasted... wait leftover=600),
        // lidl needs 1 pack of 500 (leftover=100). Both cost 0.99 -> tie -> lidl wins (less leftover).
        let best = p.bestBuy("milch", 400)
        #expect(best.total == 0.99)
        #expect(best.store == "lidl")
    }

    @MainActor
    @Test("bestBuy picks the strictly cheaper store when there is no tie")
    func bestBuyStrictlyCheaper() {
        var settings = Settings()
        settings.stores = ["aldi", "lidl"]
        let offers = OffersFile(
            kw: "t", stand: "2026-09-28", ort: nil, hinweis: nil,
            stores: [
                "aldi": StoreOffer(name: nil, market: nil, validFrom: "2026-09-01", validTo: "2026-12-31", status: nil, source: nil,
                                    items: ["milch": OfferItem(product: "Milch A", price: 1.50, pk: 1000, label: "1 l", note: nil, app: nil)]),
                "lidl": StoreOffer(name: nil, market: nil, validFrom: "2026-09-01", validTo: "2026-12-31", status: nil, source: nil,
                                    items: ["milch": OfferItem(product: "Milch B", price: 0.80, pk: 1000, label: "1 l", note: nil, app: nil)])
            ]
        )
        let p = makePlanner(settings: settings, offers: offers)
        let best = p.bestBuy("milch", 400)
        #expect(best.store == "lidl")
        #expect(best.total == 0.80)
    }

    // MARK: - Budget

    @MainActor
    @Test("fitPlan() only produces a plan over budget when no combination fits")
    func costWithinBudgetWhenPossible() {
        var settings = Settings()
        settings.stores = ["aldi", "lidl"]
        settings.persons = 2
        settings.days = 5
        settings.budget = 45
        settings.vorrat = true
        var p = makePlanner(settings: settings)
        p.fitPlan()
        // The web version accepts an over-budget plan only when nothing fits; with the
        // default 5 dinners / 2 persons / 45 € this combination is comfortably feasible.
        #expect(p.costOf(p.settings.plan) <= settings.budget)
        #expect(p.settings.plan.count == 5)
    }

    // MARK: - Diet filters

    @MainActor
    @Test("vegan diet excludes any recipe touching meat, fish, dairy or egg ingredients")
    func veganExcludesAnimalProducts() {
        var settings = Settings()
        settings.diet = "vegan"
        let p = makePlanner(settings: settings)
        let cands = p.candidates()
        #expect(!cands.isEmpty)
        for r in cands {
            #expect(r.kind == "vegan")
            for key in r.ing.keys {
                let tags = p.catalog.ing[key]?.tags ?? []
                #expect(!tags.contains("fleisch"))
                #expect(!tags.contains("fisch"))
                #expect(!tags.contains("milch"))
                #expect(!tags.contains("ei"))
            }
        }
    }

    @MainActor
    @Test("histaminarm excludes every recipe flagged as histamine-rich")
    func histExcludesHistRecipes() {
        var settings = Settings()
        settings.hist = true
        let p = makePlanner(settings: settings)
        let cands = p.candidates()
        #expect(!cands.isEmpty)
        for r in cands {
            #expect(r.hist == false)
        }
    }

    @MainActor
    @Test("glutenfrei excludes every recipe flagged as containing gluten")
    func glutExcludesGlutRecipes() {
        var settings = Settings()
        settings.glut = true
        let p = makePlanner(settings: settings)
        for r in p.candidates() { #expect(r.glut == false) }
    }

    // MARK: - Offer validity

    @MainActor
    @Test("offers outside their validity window are ignored")
    func offersIgnoredOutsideValidity() {
        let settings = Settings()
        // Offer valid 2026-09-01...2026-09-20, "today" is 2026-09-28 -> expired.
        let expired = TestFixtures.offers(validFrom: "2026-09-01", validTo: "2026-09-20")
        let pExpired = makePlanner(settings: settings, offers: expired, today: "2026-09-28")
        #expect(pExpired.offersLive("aldi") == false)
        #expect(pExpired.activeOffer("milch", "aldi") == nil)

        // Offer valid 2026-09-25...2026-10-02, "today" is 2026-09-28 -> live.
        let live = TestFixtures.offers(validFrom: "2026-09-25", validTo: "2026-10-02")
        let pLive = makePlanner(settings: settings, offers: live, today: "2026-09-28")
        #expect(pLive.offersLive("aldi") == true)
        #expect(pLive.activeOffer("milch", "aldi") != nil)

        // Not-yet-started offer.
        let future = TestFixtures.offers(validFrom: "2026-10-01", validTo: "2026-10-10")
        let pFuture = makePlanner(settings: settings, offers: future, today: "2026-09-28")
        #expect(pFuture.offersLive("aldi") == false)
    }
}
