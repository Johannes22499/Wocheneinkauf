import Foundation

/// Bit-exact ports of the small deterministic helpers in web/wochenkorb.html:
/// `hash(s)` (FNV-1a-ish) and `rng(seed)` (mulberry32).
enum PlannerMath {
    /// function hash(s){let h=2166136261;for(const c of s){h^=c.charCodeAt(0);h=Math.imul(h,16777619)}return (h>>>0)}
    static func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for scalar in s.unicodeScalars {
            h ^= UInt32(scalar.value & 0xFFFF)
            h = h &* 16777619
        }
        return h
    }

    /// function rng(seed){let a=seed>>>0;return()=>{a|=0;a=a+0x6D2B79F5|0;
    ///   let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;
    ///   return((t^t>>>14)>>>0)/4294967296}}
    static func makeRNG(seed: UInt32) -> () -> Double {
        var a: UInt32 = seed
        return {
            a = a &+ 0x6D2B79F5
            var t: UInt32 = a
            t = (t ^ (t >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
    }

    static func seed32(_ value: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: value)
    }
}

/// German number/currency formatting helpers, matching the small `eur`/`fmtQty` helpers
/// in web/wochenkorb.html.
enum DE {
    static let locale = Locale(identifier: "de_DE")

    static func number(_ n: Double, minFrac: Int = 0, maxFrac: Int = 3) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = minFrac
        f.maximumFractionDigits = maxFrac
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// eur = n => n.toLocaleString('de-DE',{minimumFractionDigits:2,maximumFractionDigits:2})+' €'
    static func eur(_ n: Double) -> String {
        number(n, minFrac: 2, maxFrac: 2) + " €"
    }
}
