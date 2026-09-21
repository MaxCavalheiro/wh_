//
//  SettingsView.swift
//  wh
//

import KeyboardShortcuts
import SwiftUI

/// Settings page shown inside the menu bar panel in place of the record/history sections.
///
/// Mirrors the main page's rhythm: 16pt between blocks, uppercase caption section headers
/// and 10pt-padded rounded cards, so switching pages feels like staying in the same panel.
struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            optionsSection
            shortcutSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .help("Back")
            .accessibilityLabel("Back to transcriptions")

            Text("Settings")
                .font(.headline)
        }
    }

    // MARK: - Sections

    private var optionsSection: some View {
        SettingsSection(title: "Options") {
            VStack(alignment: .leading, spacing: 10) {
                SettingsToggle(
                    isOn: $settings.isFastModeEnabled,
                    title: "Fast mode",
                    detail: "Click the menu bar icon to start recording and click again to transcribe, without opening the panel. Right-click opens it."
                )
                Divider()
                SettingsToggle(
                    isOn: $settings.showsQuickActions,
                    title: "Show quick actions",
                    detail: "Buttons next to each transcription's time, like Open in ChatGPT."
                )
            }
        }
    }

    private var shortcutSection: some View {
        SettingsSection(title: "Record shortcut") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    KeyboardShortcuts.Recorder(for: .toggleRecording)
                    Button("Reset") { KeyboardShortcuts.reset(.toggleRecording) }
                        .controlSize(.small)
                        .help("Back to ⌥ Space")
                }
                Text("Press a combination with ⌘, ⌥ or ⌃ (e.g. ⌥ Space) or an F-key. It works from any app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Hold to record and release to transcribe, or tap to start and tap again to stop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Pieces

/// Switch with a title and a secondary explanation, laid out like the history rows.
private struct SettingsToggle: View {
    @Binding var isOn: Bool
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Fill the row so every switch sits on the same right edge.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

/// Uppercase caption title over a rounded card, matching the history list's headers and rows.
private struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

#Preview {
    SettingsView(onBack: {})
        .environmentObject(AppSettings())
        .padding(16)
        .frame(width: 340)
}
