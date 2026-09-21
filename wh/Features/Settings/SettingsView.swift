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
            fastModeSection
            shortcutSection
            quickActionsSection
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

    private var fastModeSection: some View {
        SettingsSection(title: "Fast mode") {
            Toggle(isOn: $settings.isFastModeEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Record from the menu bar icon")
                        .font(.callout)
                    Text("Click the icon to start recording and click again to transcribe, without opening the panel. Right-click opens it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }

    private var quickActionsSection: some View {
        SettingsSection(title: "Quick actions") {
            Toggle(isOn: $settings.showsQuickActions) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show quick actions")
                        .font(.callout)
                    Text("Buttons next to each transcription's time, like Open in ChatGPT.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
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

// MARK: - Section

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
