import Testing
@testable import Wochenkorb

/// Spot-checks Catalog.price against values computed directly by the reference JS
/// (jsc-evaluated PRICE grid from web/wochenkorb.html), to make sure the Swift port
/// of hash()/jitter/rounding matches bit-for-bit.
@Suite("Price cross-check vs. JS reference")
struct PriceCrossCheckTests {
    @MainActor
    @Test("Swift PRICE grid matches the JS-computed values for spot-checked pairs")
    func matchesJSReference() {
        let catalog = TestFixtures.catalog
        // Values captured via `jsc` running the original web/wochenkorb.html data+PRICE block.
        let expected: [(ing: String, store: String, price: Double)] = [
            ("spaghetti", "aldi", 0.89),
            ("spaghetti", "rewe", 1.19),
            ("haehnchen", "kaufland", 3.89),
            ("haehnchen", "edeka", 4.59),
            ("milch", "kaufland", 1.09),
            ("milch", "edeka", 1.19),
        ]
        for (ing, store, price) in expected {
            let actual = catalog.price[ing]?[store]
            #expect(actual == price, "\(ing)/\(store): expected \(price), got \(String(describing: actual))")
        }
    }
}
