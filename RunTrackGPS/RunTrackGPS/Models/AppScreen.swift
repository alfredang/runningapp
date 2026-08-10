import Foundation

/// Drives top-level navigation. The app is intentionally lightweight, so instead
/// of a NavigationStack we switch on this enum inside `RootView`.
enum AppScreen {
    case home
    case running
    case completion
}

/// The bottom tabs, used as `TabView` selection tags so features like
/// "Run It Again" (History) can switch tabs programmatically.
enum AppTab: Hashable {
    case run
    case history
    case settings
    case feedback
    case about
}
