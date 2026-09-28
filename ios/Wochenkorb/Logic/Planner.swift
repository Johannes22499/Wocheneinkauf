import Foundation

/// Pure planning/pricing logic, ported 1:1 from the `<script>` block of web/wochenkorb.html
/// (candidates/matches, option/bestBuy/packsFor, needs/costOf, samplePlan/generate/fitPlan,
/// buildList/listText). No UI, fully testable.
struct Planner {
    let catalog: Catalog
    let offers: OffersFile?
    var settings: Settings
    /// "yyyy-MM-dd", injectable so tests can pin "today".
    let today: String

    init(catalog: Catalog, offers: OffersFile?, settings: Settings, today: String = Planner.todayString()) {
        self.catalog = catalog
        self.offers = offers
        self.settings = settings
        self.today = today
    }

    static func todayString(_ date: Date = Date()) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - Diet / filter matching

    func matches(_ r: Recipe) -> Bool {
        if settings.diet == "fleisch", !(r.kind == "fleisch" || r.kind == "fisch") { return false }
        if settings.diet == "veg", !(r.kind == "veg" || r.kind == "vegan") { return false }
        if settings.diet == "vegan", r.kind != "vegan" { return false }
        if settings.hist, r.hist { return false }
        if settings.lakt, r.lakt { return false }
        if settings.glut, r.glut { return false }
        return true
    }

    func candidates() -> [Recipe] { catalog.recipes.filter(matches) }

    // MARK: - Offers

    func offersLive(_ store: String) -> Bool {
        guard let o = offers?.stores[store] else { return false }
        return o.validFrom <= today && today <= o.validTo
    }

    func activeOffer(_ ingID: String, _ store: String) -> OfferItem? {
        guard offersLive(store) else { return nil }
        guard let o = offers?.stores[store]?.items[ingID] else { return nil }
        if let isApp = o.app, isApp, !settings.app { return nil }
        return o
    }

    // MARK: - Buying options

    struct Option {
        let store: String
        let pk: Double
        let price: Double
        let label: String
        let offer: OfferItem?
    }

    func pkLabel(_ i: Ingredient) -> String {
        if let label = i.pkLabel { return label }
        if i.unit == "Stk", i.pk == 1 { return "Stück" }
        if i.unit == "Bund" { return "Bund" }
        return fmtQty(i.pk, i.unit)
    }

    func option(_ ingID: String, _ store: String) -> Option {
        let i = catalog.ing[ingID]!
        if let o = activeOffer(ingID, store) {
            return Option(store: store, pk: o.pk, price: o.price, label: o.label, offer: o)
        }
        let price = catalog.price[ingID]?[store] ?? 0
        return Option(store: store, pk: i.pk, price: price, label: pkLabel(i), offer: nil)
    }

    /// function packsFor(q,pk){ return Math.max(1,Math.ceil(q/pk-0.03)); }
    func packsFor(_ q: Double, _ pk: Double) -> Int {
        max(1, Int(ceil(q / pk - 0.03)))
    }

    struct Buy {
        let store: String
        let option: Option
        let n: Int
        let total: Double
    }

    func bestBuy(_ ingID: String, _ q: Double) -> Buy {
        var best: Buy?
        for store in settings.stores {
            let o = option(ingID, store)
            let n = packsFor(q, o.pk)
            let t = Double(n) * o.price
            if best == nil
                || t < best!.total - 0.001
                || (abs(t - best!.total) < 0.001 && Double(n) * o.pk < Double(best!.n) * best!.option.pk) {
                best = Buy(store: store, option: o, n: n, total: t)
            }
        }
        return best!
    }

    func unitPrice(_ ingID: String) -> Double {
        settings.stores.map { store -> Double in
            let o = option(ingID, store)
            return o.price / o.pk
        }.min() ?? 0
    }

    func onOffer(_ ingID: String) -> Bool {
        settings.stores.contains { activeOffer(ingID, $0) != nil }
    }

    // MARK: - Needs / cost

    func needs(_ plan: [String]) -> [String: Double] {
        var need: [String: Double] = [:]
        for rid in plan {
            guard let r = catalog.recipesByID[rid] else { continue }
            for (k, q) in r.ing {
                need[k, default: 0] += q * Double(settings.persons)
            }
        }
        return need
    }

    private func isPantryBasic(_ ingID: String) -> Bool {
        settings.vorrat && (catalog.ing[ingID]?.tags.contains("basic") ?? false)
    }

    func costOf(_ plan: [String]) -> Double {
        var t = 0.0
        for (k, q) in needs(plan) {
            if isPantryBasic(k) { continue }
            t += bestBuy(k, q).total
        }
        return t
    }

    func offerCount(_ plan: [String]) -> Int {
        needs(plan).keys.filter(onOffer).count
    }

    func portionPrice(_ r: Recipe) -> Double {
        var t = 0.0
        for (k, q) in r.ing {
            if isPantryBasic(k) { continue }
            t += q * unitPrice(k)
        }
        return t
    }

    // MARK: - Planning

    func samplePlan(_ n: Int, _ keep: [String], _ rand: () -> Double, pool: [String]? = nil) -> [String] {
        let pool = pool ?? candidates().map(\.id)
        var out = keep
        if pool.isEmpty { return out }
        var avail = pool.filter { !out.contains($0) }
        while out.count < n {
            if avail.isEmpty { avail = pool }
            let i = min(Int(rand() * Double(avail.count)), avail.count - 1)
            out.append(avail.remove(at: i))
        }
        return out
    }

    func generate(keep: [String] = []) -> [String] {
        let seedRaw = Int64(settings.seed) * 9973 + Int64(settings.days) * 31 + Int64(settings.persons)
        let rand = PlannerMath.makeRNG(seed: UInt32(truncatingIfNeeded: seedRaw))
        let n = settings.days
        let pool = candidates().map(\.id)
        var under: [[String]] = []
        var best: (p: [String], c: Double)?
        for _ in 0..<600 {
            let p = samplePlan(n, keep, rand, pool: pool)
            let c = costOf(p)
            if best == nil || c < best!.c { best = (p, c) }
            if c <= settings.budget { under.append(p) }
            if under.count >= 40 { break }
        }
        if !keep.isEmpty, under.isEmpty { return generate(keep: []) }
        if under.isEmpty { return best?.p ?? [] }
        let ranked = under.map { (p: $0, o: offerCount($0)) }.sorted { $0.o > $1.o }
        let topCount = max(6, Int(ceil(Double(ranked.count) / 3)))
        let top = Array(ranked.prefix(topCount))
        let idx = min(Int(rand() * Double(top.count)), top.count - 1)
        return top[idx].p
    }

    mutating func fitPlan() {
        var keep = settings.plan.filter { id in catalog.recipesByID[id].map(matches) ?? false }
        keep = Array(keep.prefix(settings.days))
        if keep.count == settings.days, costOf(keep) <= settings.budget {
            settings.plan = keep
            return
        }
        settings.plan = generate(keep: keep.count < settings.days ? keep : [])
    }

    // MARK: - Shopping list

    struct ShoppingItem: Identifiable, Equatable {
        var id: String { key + "@" + store }
        let key: String
        let name: String
        let cat: String
        let packs: Int
        let store: String
        let unitPrice: Double
        let pk: Double
        let sum: Double
        let rest: Double
        let unit: String
        let label: String
        let isOffer: Bool
        let offerNote: String?
        let saved: Double
    }

    func buildList() -> (items: [ShoppingItem], pantry: [String]) {
        let need = needs(settings.plan)
        var items: [ShoppingItem] = []
        var pantry: [String] = []
        for (k, q) in need {
            guard let i = catalog.ing[k] else { continue }
            if settings.vorrat, i.tags.contains("basic") { pantry.append(i.name); continue }
            let b = bestBuy(k, q)
            let reg: Double
            if b.option.offer != nil {
                reg = Double(packsFor(q, i.pk)) * (catalog.price[k]?[b.store] ?? 0)
            } else {
                reg = b.total
            }
            items.append(ShoppingItem(
                key: k,
                name: b.option.offer?.product ?? i.name,
                cat: i.cat,
                packs: b.n,
                store: b.store,
                unitPrice: b.option.price,
                pk: b.option.pk,
                sum: b.total,
                rest: Double(b.n) * b.option.pk - q,
                unit: i.unit,
                label: b.option.label,
                isOffer: b.option.offer != nil,
                offerNote: b.option.offer?.note,
                saved: max(0, reg - b.total)
            ))
        }
        return (items, pantry)
    }

    func fmtQty(_ q: Double, _ u: String) -> String {
        if u == "g" || u == "ml" {
            let v = q >= 100 ? (q / 10).rounded() * 10 : (q / 5).rounded() * 5
            if v >= 1000 {
                return DE.number(v / 1000, minFrac: 0, maxFrac: 2) + (u == "g" ? " kg" : " l")
            }
            return "\(Int(v)) \(u)"
        }
        let v = (q * 2).rounded() / 2
        let s = DE.number(v, minFrac: 0, maxFrac: 3)
        if u == "Zehe" { return s + (v == 1 ? " Zehe" : " Zehen") }
        return s + " " + u
    }

    func basePriceDisplay(_ ingID: String, _ price: Double, _ pk: Double?) -> String? {
        guard let i = catalog.ing[ingID] else { return nil }
        let pkVal = pk ?? i.pk
        if i.unit == "g" { return DE.eur(price / pkVal * 1000) + "/kg" }
        if i.unit == "ml" { return DE.eur(price / pkVal * 1000) + "/l" }
        return nil
    }

    func listText() -> String {
        let (items, pantry) = buildList()
        var lines = ["Einkaufsliste KW \(Self.isoWeek(Date()))"]
        for store in settings.stores {
            let l = items.filter { $0.store == store }
            if l.isEmpty { continue }
            lines.append("")
            lines.append((catalog.stores[store]?.name ?? store).uppercased())
            for cat in catalog.catOrder {
                for it in l.filter({ $0.cat == cat }) {
                    var line = "[ ] \(it.packs)× \(it.name) (\(it.label)) – \(DE.eur(it.sum))"
                    if it.isOffer {
                        line += " · ANGEBOT" + (it.offerNote.map { " (\($0))" } ?? "")
                    }
                    lines.append(line)
                }
            }
        }
        lines.append("")
        lines.append("Summe: \(DE.eur(items.reduce(0) { $0 + $1.sum }))")
        lines.append("")
        lines.append("Rezepte:")
        for (i, id) in settings.plan.enumerated() {
            let name = catalog.recipesByID[id]?.name ?? id
            let day = i < DayNames.short.count ? DayNames.short[i] : "+"
            lines.append("\(day): \(name)")
        }
        if !pantry.isEmpty {
            lines.append("")
            lines.append("Vorrat: \(pantry.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    static func isoWeek(_ date: Date) -> Int {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone.current
        return cal.component(.weekOfYear, from: date)
    }
}
