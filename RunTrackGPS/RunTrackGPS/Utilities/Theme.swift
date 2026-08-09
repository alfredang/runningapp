import SwiftUI

/// The app's visual language: a warm light-grey canvas with white elevated cards.
///
/// The app forces `.light` appearance (see `RunTrackGPSApp`), so these are fixed
/// sRGB values rather than semantic system colors — the previous all-black look
/// came from `Color(.systemBackground)` following the device's dark mode. Use
/// `Theme.canvas` for screen backgrounds and `Theme.card` for raised surfaces.
enum Theme {

    /// Warm light-grey page background.
    static let canvas = Color(red: 0.949, green: 0.945, blue: 0.937)      // #F2F1EF
    /// Raised surface (cards, rows, sheets).
    static let card = Color.white
    /// A slightly tinted surface for nested/secondary fills inside a card.
    static let cardMuted = Color(red: 0.965, green: 0.961, blue: 0.953)   // #F6F5F3

    /// Primary brand accent. Follows the palette chosen in Settings (default the
    /// vivid running orange, #EF6728) — computed rather than `let` so every view
    /// picks up a theme change immediately.
    static var accent: Color { AppSettings.shared.accentTheme.color }
    /// Deep ink used for headline text on the light canvas.
    static let ink = Color(red: 0.106, green: 0.114, blue: 0.129)         // #1B1D21
    /// Muted secondary text.
    static let inkSecondary = Color(red: 0.412, green: 0.427, blue: 0.459) // #696D75

    /// Supporting hues for status chips and stats.
    static let success = Color(red: 0.180, green: 0.667, blue: 0.400)     // #2EAA66
    static let warning = Color(red: 0.945, green: 0.686, blue: 0.192)     // #F1AF31
    static let danger  = Color(red: 0.878, green: 0.267, blue: 0.267)     // #E04444
    static let info    = Color(red: 0.204, green: 0.478, blue: 0.902)     // #347AE6

    /// Standard corner radius for cards.
    static let cornerRadius: CGFloat = 18
    /// Soft ambient shadow used by `.cardStyle()`.
    static let shadow = Color.black.opacity(0.06)
}

// MARK: - Reusable surface styling

extension View {

    /// Wraps the view in the standard white elevated card.
    func cardStyle(padding: CGFloat = 16,
                   cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius,
                                                        style: .continuous))
            .shadow(color: Theme.shadow, radius: 10, x: 0, y: 4)
    }

    /// Applies the warm-grey page canvas behind the view.
    func canvasBackground() -> some View {
        self.background(Theme.canvas.ignoresSafeArea())
    }
}
