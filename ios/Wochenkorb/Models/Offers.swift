import Foundation

/// Matches angebote/2026-KW40.json / offers_fallback.json / the future AKTUELL.json.
struct OffersFile: Codable, Sendable {
    let kw: String
    let stand: String
    let ort: String?
    let hinweis: String?
    let stores: [String: StoreOffer]
}

struct StoreOffer: Codable, Sendable {
    let name: String?
    let market: String?
    let validFrom: String
    let validTo: String
    let status: String?
    let source: String?
    let items: [String: OfferItem]
}

struct OfferItem: Codable, Sendable {
    let product: String
    let price: Double
    let pk: Double
    let label: String
    let note: String?
    let app: Bool?
}
