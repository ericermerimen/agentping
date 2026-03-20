import SwiftUI

/// Shared color for context window progress bars.
/// Used by ExpandedRowView and SessionHoverView.
func contextBarColor(_ pct: Double) -> Color {
    if pct > 0.85 { return Color(.systemRed).opacity(0.8) }
    if pct > 0.65 { return Color(.systemOrange).opacity(0.7) }
    return Color(.systemGreen).opacity(0.5)
}
