import Foundation

/// The two routing-rule families Xray supports for bypass: domain-based
/// (`geosite:` / hostnames, matched against the `domain` field) and IP-based
/// (`geoip:` / CIDR, matched against the `ip` field).
enum BypassRuleKind {
    case geosite
    case geoip
}

/// A single Xray routing tag plus the field it belongs to.
struct BypassTag: Hashable {
    let kind: BypassRuleKind
    /// Full Xray rule value, e.g. `geosite:category-ir` or `geoip:private`.
    let value: String
}

/// A user-selectable bypass category. Each one can expand to several underlying
/// Xray tags spanning both domain and IP rules (e.g. "Iran" covers Iranian
/// domains *and* Iranian IP ranges). `id` is a stable key persisted in settings.
struct GeositeCategory: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let tags: [BypassTag]
}

/// Curated list of common categories users are most likely to bypass. The tags
/// reference data baked into the bundled `geosite.dat` / `geoip.dat`. Anything
/// not covered here can be added through the custom-entry field.
enum GeositeCatalog {
    static let categories: [GeositeCategory] = [
        GeositeCategory(
            id: "category-ir",
            label: "Iran",
            detail: "Iranian sites & IP ranges",
            tags: [
                BypassTag(kind: .geosite, value: "geosite:category-ir"),
                BypassTag(kind: .geoip, value: "geoip:ir"),
            ]
        ),
        GeositeCategory(
            id: "category-ads-all",
            label: "Ads",
            detail: "Ad & tracker domains (analytics, doubleclick…)",
            tags: [
                BypassTag(kind: .geosite, value: "geosite:category-ads-all"),
            ]
        ),
        GeositeCategory(
            id: "private",
            label: "Private / LAN",
            detail: "Local & private IPs (router, NAS, other LAN devices)",
            tags: [
                BypassTag(kind: .geoip, value: "geoip:private"),
            ]
        ),
    ]

    static func category(for id: String) -> GeositeCategory? {
        categories.first { $0.id == id }
    }
}
