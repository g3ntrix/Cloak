import Foundation

/// A single selectable geosite category. `id` is the raw geosite tag (without the
/// `geosite:` prefix) as it appears in the bundled `geosite.dat`.
struct GeositeCategory: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String

    /// The routing-rule form Xray expects, e.g. `geosite:cn`.
    var domainTag: String { "geosite:\(id)" }
}

/// Curated list of common geosite categories users are most likely to bypass.
/// These are stable tags from the v2fly/domain-list-community set baked into the
/// bundled `geosite.dat`. Not exhaustive — custom entries cover the rest.
enum GeositeCatalog {
    static let categories: [GeositeCategory] = [
        GeositeCategory(id: "category-ir", label: "Iran", detail: "Iranian sites & local services"),
        GeositeCategory(id: "category-ads-all", label: "Ads", detail: "Ad & tracker domains (analytics, doubleclick…)"),
        GeositeCategory(id: "private", label: "Private / LAN", detail: "Local & private network addresses"),
    ]

    static func category(for id: String) -> GeositeCategory? {
        categories.first { $0.id == id }
    }
}
