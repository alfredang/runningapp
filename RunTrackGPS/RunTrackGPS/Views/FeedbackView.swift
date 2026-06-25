import SwiftUI

/// Feedback tab (Tertiary Infotech house style): a Title + Message form whose
/// "Send via WhatsApp" button opens a pre-filled chat to the support number.
struct FeedbackView: View {
    /// +65 8866 6375 — Singapore country code, no "+" or spaces (wa.me format).
    private let whatsAppNumber = "6588666375"

    @State private var title = ""
    @State private var message = ""
    @FocusState private var fieldFocused: Bool

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("We'd love your feedback on RunTrack GPS. Send it over WhatsApp and we'll get back to you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Title
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title").font(.headline)
                        TextField("e.g. Feature request", text: $title)
                            .focused($fieldFocused)
                            .padding(14)
                            .background(Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Message
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message").font(.headline)
                        ZStack(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("Your message…")
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 22)
                            }
                            TextEditor(text: $message)
                                .focused($fieldFocused)
                                .scrollContentBackground(.hidden)   // iOS 16+: show custom background
                                .frame(minHeight: 160)
                                .padding(8)
                        }
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: send) {
                        Label("Send via WhatsApp", systemImage: "paperplane.fill")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(!canSend)
                }
                .padding(20)
            }
            .navigationTitle("Feedback")
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { fieldFocused = false }
        }
    }

    private func send() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

        var body = ""
        if !trimmedTitle.isEmpty { body += "*\(trimmedTitle)*\n" }
        body += trimmedMessage

        // Build the wa.me URL with URLComponents so the text is percent-encoded
        // correctly (newlines, "*", emoji). https link works with or without the app.
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "wa.me"
        comps.path = "/\(whatsAppNumber)"
        comps.queryItems = [URLQueryItem(name: "text", value: body)]
        if let url = comps.url {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    FeedbackView()
}
