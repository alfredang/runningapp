import SwiftUI

/// Settings tab: audio-coaching behaviour and the app's accent palette.
struct SettingsView: View {

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    audioSection
                    musicSection
                    themeSection
                }
                .padding(20)
            }
            .canvasBackground()
            .navigationTitle("Settings")
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Audio Coaching", systemImage: "speaker.wave.2.fill")

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $settings.voiceOverOtherAudio) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Play over music & videos")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Speak your kilometre splits and goal alerts while you're listening to music, a podcast, or YouTube. Your audio is briefly lowered, then restored.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                .tint(Theme.accent)

                if !settings.voiceOverOtherAudio {
                    Label("Coaching stays silent while another app is playing audio.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .transition(.opacity)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach volume")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(Theme.inkSecondary)
                        Slider(value: $settings.coachVolume, in: 0.2...1.0)
                            .tint(Theme.accent)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    Text("How loud the voice coach speaks. Your music's own volume is set in its app — iOS doesn't allow apps to change each other's volume.")
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .cardStyle()
        }
        .animation(.easeInOut(duration: 0.2), value: settings.voiceOverOtherAudio)
    }

    // MARK: - Music

    /// Favourite music app, quick-launchable from the Home screen before a run.
    private var musicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Music", systemImage: "music.note")

            VStack(spacing: 0) {
                ForEach(MusicApp.allCases) { app in
                    musicRow(app)
                    Divider().foregroundStyle(Theme.cardMuted)
                }
                // "None" row clears the selection and hides the Home quick-launch.
                Button {
                    settings.favouriteMusicApp = nil
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "nosign")
                            .frame(width: 28)
                            .foregroundStyle(Theme.inkSecondary)
                        Text("None")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        if settings.favouriteMusicApp == nil {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .cardStyle()

            Text("Your pick appears on the Home screen so you can start your music just before you run.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSecondary)
        }
    }

    private func musicRow(_ app: MusicApp) -> some View {
        Button {
            settings.favouriteMusicApp = app
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "music.note.list")
                    .frame(width: 28)
                    .foregroundStyle(Theme.accent)
                Text(app.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if settings.favouriteMusicApp == app {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(settings.favouriteMusicApp == app ? [.isSelected] : [])
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Colour Theme", systemImage: "paintpalette.fill")

            VStack(spacing: 0) {
                ForEach(Array(AccentTheme.allCases.enumerated()), id: \.element.id) { index, theme in
                    Button {
                        settings.accentTheme = theme
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 28, height: 28)
                            Text(theme.displayName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            if settings.accentTheme == theme {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(theme.color)
                            }
                        }
                        .frame(minHeight: 56)          // HIG touch target
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(settings.accentTheme == theme ? [.isSelected] : [])

                    if index < AccentTheme.allCases.count - 1 {
                        Divider().foregroundStyle(Theme.cardMuted)
                    }
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.title3.bold())
            .foregroundStyle(Theme.ink)
    }
}
