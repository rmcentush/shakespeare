import SwiftUI

struct SettingsView: View {
    @State private var anthropicKey = ""
    @State private var showKey = false
    @State private var saved = false

    // Font settings
    @State private var fontManager = FontManager.shared
    @State private var textCheckingSettings = TextCheckingSettings.shared

    var body: some View {
        TabView {
            // API Keys tab
            Form {
                Section("Anthropic API Key") {
                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $anthropicKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("sk-ant-...", text: $anthropicKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                    }

                    HStack {
                        Button("Save") {
                            KeychainService.shared.setAPIKey(anthropicKey, service: "anthropic")
                            saved = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                saved = false
                            }
                        }
                        if saved {
                            Text("Saved!")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Text("Your API key is stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("API Keys", systemImage: "key") }

            // Typography tab
            Form {
                Section("Font") {
                    Picker("Font Family", selection: $fontManager.currentFont) {
                        Text("Lyon Text").tag("Lyon Text")
                        Text("Source Serif 4").tag("Source Serif 4")
                        Text("Scala").tag("Scala")
                        Text("Charter").tag("Charter")
                        Text("Signifier").tag("Signifier")
                        Text("EBGaramond").tag("EBGaramond")
                        Text("Times New Roman").tag("Times New Roman")
                        Text("Georgia").tag("Georgia")
                        Text("Palatino").tag("Palatino")
                        Text("Baskerville").tag("Baskerville")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                        Text("San Francisco").tag("-apple-system")
                    }

                    HStack {
                        Text("Font Size: \(Int(fontManager.currentSize))px")
                        Slider(value: $fontManager.currentSize, in: 12...28, step: 1)
                    }

                    HStack {
                        Text("Line Height: \(String(format: "%.1f", fontManager.currentLineHeight))")
                        Slider(value: $fontManager.currentLineHeight, in: 1.2...2.5, step: 0.1)
                    }
                }

                Section {
                    Button("Apply & Save") {
                        fontManager.save()
                        NotificationCenter.default.post(name: .fontSettingsChanged, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .tabItem { Label("Typography", systemImage: "textformat") }

            Form {
                Section("Spelling and Grammar") {
                    Toggle("Check spelling while typing", isOn: Binding(
                        get: { textCheckingSettings.continuousSpellCheckingEnabled },
                        set: { textCheckingSettings.continuousSpellCheckingEnabled = $0 }
                    ))

                    Toggle("Check grammar with spelling", isOn: Binding(
                        get: { textCheckingSettings.grammarCheckingEnabled },
                        set: { textCheckingSettings.grammarCheckingEnabled = $0 }
                    ))

                    Toggle("Correct spelling automatically", isOn: Binding(
                        get: { textCheckingSettings.automaticSpellingCorrectionEnabled },
                        set: { textCheckingSettings.automaticSpellingCorrectionEnabled = $0 }
                    ))
                }

                Section("Substitutions") {
                    Toggle("Use text replacements", isOn: Binding(
                        get: { textCheckingSettings.automaticTextReplacementEnabled },
                        set: { textCheckingSettings.automaticTextReplacementEnabled = $0 }
                    ))
                }

                Section {
                    Text("These settings use macOS and WebKit text checking for the editor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("Editing", systemImage: "checkmark.circle") }
        }
        .frame(width: 450, height: 360)
        .onAppear {
            if let key = KeychainService.shared.getAPIKey(service: "anthropic") {
                anthropicKey = key
            }
        }
    }
}

extension Notification.Name {
    static let fontSettingsChanged = Notification.Name("fontSettingsChanged")
}
