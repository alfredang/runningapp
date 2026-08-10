import SwiftUI
import Combine

/// Selectable accent palettes. The app keeps its warm light-grey canvas in every
/// case — only the accent hue (and the supporting run-status tints derived from it)
/// changes, so contrast on the light surfaces stays within HIG guidance.
enum AccentTheme: String, CaseIterable, Identifiable {
    case orange
    case blue
    case green
    case purple
    case pink

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orange: return "Sunset"
        case .blue:   return "Ocean"
        case .green:  return "Forest"
        case .purple: return "Twilight"
        case .pink:   return "Bloom"
        }
    }

    /// The accent colour used for buttons, the tab bar tint, and the route line.
    var color: Color {
        switch self {
        case .orange: return Color(red: 0.937, green: 0.404, blue: 0.157)   // #EF6728
        case .blue:   return Color(red: 0.129, green: 0.451, blue: 0.886)   // #2173E2
        case .green:  return Color(red: 0.118, green: 0.612, blue: 0.365)   // #1E9C5D
        case .purple: return Color(red: 0.478, green: 0.318, blue: 0.859)   // #7A51DB
        case .pink:   return Color(red: 0.851, green: 0.243, blue: 0.494)   // #D93E7E
        }
    }
}

/// Music apps the runner can quick-launch before a run. Opened via their https
/// universal links, which iOS routes to the installed app automatically (and to
/// the website when the app isn't installed) — no URL-scheme queries needed.
enum MusicApp: String, CaseIterable, Identifiable {
    case appleMusic
    case spotify
    case youtubeMusic
    case youtube

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleMusic:   return "Apple Music"
        case .spotify:      return "Spotify"
        case .youtubeMusic: return "YouTube Music"
        case .youtube:      return "YouTube"
        }
    }

    var url: URL {
        switch self {
        case .appleMusic:   return URL(string: "https://music.apple.com")!
        case .spotify:      return URL(string: "https://open.spotify.com")!
        case .youtubeMusic: return URL(string: "https://music.youtube.com")!
        case .youtube:      return URL(string: "https://www.youtube.com")!
        }
    }
}

/// User preferences persisted in `UserDefaults`.
///
/// A singleton because `Theme` is consumed by static accessors throughout the view
/// layer; `objectWillChange` drives a SwiftUI refresh when either setting changes.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum Key {
        static let accent = "settings.accentTheme"
        static let duckOtherAudio = "settings.voiceOverOtherAudio"
        static let coachVolume = "settings.coachVolume"
        static let musicApp = "settings.favouriteMusicApp"
    }

    /// The runner's favourite music app, quick-launchable from Home. `nil` = none.
    @Published var favouriteMusicApp: MusicApp? {
        didSet {
            guard favouriteMusicApp != oldValue else { return }
            defaults.set(favouriteMusicApp?.rawValue ?? "", forKey: Key.musicApp)
        }
    }

    /// Selected accent palette.
    @Published var accentTheme: AccentTheme {
        didSet {
            guard accentTheme != oldValue else { return }
            defaults.set(accentTheme.rawValue, forKey: Key.accent)
        }
    }

    /// When `true` (the default) spoken coaching plays over Music/YouTube, ducking
    /// them for the announcement. When `false` the runner has chosen to keep their
    /// media untouched, so coaching stays silent while another app is playing.
    @Published var voiceOverOtherAudio: Bool {
        didSet {
            guard voiceOverOtherAudio != oldValue else { return }
            defaults.set(voiceOverOtherAudio, forKey: Key.duckOtherAudio)
        }
    }

    /// Loudness of the voice coach's announcements (0.2–1.0, default full volume).
    /// Note this scales OUR speech only — iOS does not allow one app to change
    /// another app's volume, and the system fixes the ducking level, so the music
    /// side of the balance is not adjustable by any app.
    @Published var coachVolume: Double {
        didSet {
            guard coachVolume != oldValue else { return }
            defaults.set(coachVolume, forKey: Key.coachVolume)
        }
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Key.accent) ?? ""
        self.accentTheme = AccentTheme(rawValue: raw) ?? .orange
        // `object(forKey:)` distinguishes "never set" (→ default ON) from an explicit
        // `false`; `bool(forKey:)` alone would silently default the feature to OFF.
        self.voiceOverOtherAudio = (defaults.object(forKey: Key.duckOtherAudio) as? Bool) ?? true
        self.coachVolume = (defaults.object(forKey: Key.coachVolume) as? Double) ?? 1.0
        self.favouriteMusicApp = MusicApp(rawValue: defaults.string(forKey: Key.musicApp) ?? "")
    }
}
