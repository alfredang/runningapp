import Foundation

/// Drives top-level navigation. The app is intentionally lightweight, so instead
/// of a NavigationStack we switch on this enum inside `RootView`.
enum AppScreen {
    case home
    case running
    case completion
}
