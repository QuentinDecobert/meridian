import Foundation

/// Strict-consumption status derived from the hero percentage
/// (`Tous les modèles` — cf. Flight Deck spec, note of design #2).
///
/// ```
///  0          : unused    (fenêtre fraîche, accent neutre ivoire)
///  1-49       : serene    (ivoire, touche d'ambre — pip de marque)
///  50-79      : watch     (ambre dominant, triangle)
///  ≥ 80       : critical  (rouge, carré plein, pip pulsant)
/// ```
///
/// The status also drives the menu-bar icon (arc + pip color), the popover
/// background gradient tint and the status glyph shape. Per the accessibility
/// rule "color-not-only", a status is **always** communicated by:
///  - a color (accent)
///  - a shape (status glyph : dashed circle / circle / triangle / square)
///  - a word (`Non utilisé`, `Serein`, `À surveiller`, `Critique`)
enum QuotaStatus: String, CaseIterable, Sendable, Equatable {
    case unused
    case serene
    case watch
    case critical

    /// Rounds the percentage (half-up) before thresholding — `49.6 %` is
    /// perceived as `50 %` by the user and should escalate to `watch`.
    static func from(percent: Double) -> QuotaStatus {
        let rounded = Int(percent.rounded())
        switch rounded {
        case ..<1:     return .unused
        case 1..<50:   return .serene
        case 50..<80:  return .watch
        default:       return .critical
        }
    }

    /// Human label used in the hero "Statut · <label>" line. French (baseline).
    /// Localized via `String(localized:)` so future en/fr table can override.
    var label: String {
        switch self {
        case .unused:   return String(localized: "status.unused",   defaultValue: "unused")
        case .serene:   return String(localized: "status.serene",   defaultValue: "serene")
        case .watch:    return String(localized: "status.watch",    defaultValue: "watch")
        case .critical: return String(localized: "status.critical", defaultValue: "critical")
        }
    }
}
