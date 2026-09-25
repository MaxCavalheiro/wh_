//
//  MenuBarPanelView.swift
//  wh
//

import SwiftUI

/// Content of the popover shown when the status bar icon is clicked.
struct MenuBarPanelView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var copiedEntryID: UUID?
    @State private var isShowingSettings = false

    var body: some View {
        VStack(spacing: 16) {
            if isShowingSettings {
                SettingsView(onBack: { isShowingSettings = false })
            } else {
                recordSection
                Divider()
                historySection
                if let notice = viewModel.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
            }
            Divider()
            footer
        }
        .animation(.default, value: viewModel.notice)
        .padding(16)
        .frame(width: 340)
        // Settings is a detour, not a place to stay: the next time the panel opens it
        // should be on the transcriptions again. (The app has a single popover.)
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            isShowingSettings = false
        }
    }

    // MARK: - Record controls

    private var recordSection: some View {
        VStack(spacing: 12) {
            controls

            if viewModel.state.isRecording {
                Text(viewModel.formattedDuration)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            if case .preparingModel(.downloading(let progress)) = viewModel.state,
               let progress, progress > 0, progress < 1 {
                ProgressView(value: progress)
                    .frame(maxWidth: 200)
            } else if case .preparingModel(.optimizing) = viewModel.state {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 200)
            }

            if let status = viewModel.state.statusText {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.center)
            }

            if case .failed(let error) = viewModel.state, error.canOpenPrivacySettings {
                Button("Open System Settings") { viewModel.openMicrophoneSettings() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.state {
        case .ready:
            CircleButton(symbol: "mic.fill", tint: Theme.brand, label: "Start recording") {
                Task { await viewModel.startRecording() }
            }
        case .recording:
            HStack(spacing: 24) {
                CircleButton(symbol: "stop.fill", tint: .red, label: "Stop and transcribe", pulsing: true) {
                    Task { await viewModel.stopRecording() }
                }
                CircleButton(symbol: "xmark", tint: Color(nsColor: .tertiaryLabelColor), label: "Cancel recording") {
                    viewModel.cancelRecording()
                }
                .keyboardShortcut(.cancelAction)
            }
        case .failed:
            CircleButton(symbol: "arrow.clockwise", tint: Color(nsColor: .systemRed), label: "Try again") {
                viewModel.reset()
            }
        case .preparingModel, .transcribing:
            CircleButton(symbol: "mic.fill", tint: Color(nsColor: .quaternaryLabelColor), label: "Busy", showsSpinner: true) {}
                .disabled(true)
        }
    }

    private var statusColor: Color {
        if case .failed = viewModel.state { return .red }
        return .secondary
    }

    // MARK: - History

    private var historySection: some View {
        Group {
            if viewModel.history.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No transcriptions yet")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.historySections) { section in
                            Section {
                                ForEach(section.entries) { entry in
                                    HistoryRow(
                                        entry: entry,
                                        isCopied: copiedEntryID == entry.id,
                                        showsQuickActions: settings.showsQuickActions,
                                        onCopy: { copy(entry) },
                                        onOpenInChatGPT: { Task { await viewModel.openInChatGPT(entry) } }
                                    )
                                    .onAppear { viewModel.loadMoreHistoryIfNeeded(after: entry) }
                                }
                            } header: {
                                SectionHeader(day: section.day)
                            }
                        }
                        if viewModel.hasMoreHistory {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                    }
                    .clickDragScrolling()
                }
                .frame(height: Self.historyHeight)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    /// Roughly three rows, so the panel keeps a stable size while the list scrolls.
    private static let historyHeight: CGFloat = 300

    private func copy(_ entry: TranscriptionEntry) {
        viewModel.copy(entry)
        copiedEntryID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedEntryID == entry.id { copiedEntryID = nil }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Label("Local Transcription", systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                isShowingSettings.toggle()
            } label: {
                Image(systemName: isShowingSettings ? "gearshape.fill" : "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(isShowingSettings ? Color.accentColor : Color.secondary)
            .keyboardShortcut(",")
            .help(isShowingSettings ? "Back" : "Settings")
            .accessibilityLabel(isShowingSettings ? "Back to transcriptions" : "Settings")
            Button {
                viewModel.quit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
            .help("Quit")
            .accessibilityLabel("Quit")
        }
    }
}

// MARK: - Circle button

private struct CircleButton: View {
    let symbol: String
    let tint: Color
    let label: String
    var pulsing = false
    var showsSpinner = false
    let action: () -> Void

    @State private var isPulsing = false

    private static let size: CGFloat = 64

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: Self.size, height: Self.size)
                    .scaleEffect(pulsing && isPulsing ? 1.06 : 1.0)
                    .animation(
                        pulsing ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                        value: isPulsing
                    )
                if showsSpinner {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { isPulsing = pulsing }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - History list pieces

private struct SectionHeader: View {
    let day: Date

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true  // "Today", "Yesterday", then full dates
        return formatter
    }()

    var body: some View {
        Text(Self.formatter.string(from: day))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }
}

private struct HistoryRow: View {
    let entry: TranscriptionEntry
    let isCopied: Bool
    /// Shows the small action buttons next to the time (see `AppSettings.showsQuickActions`).
    let showsQuickActions: Bool
    let onCopy: () -> Void
    let onOpenInChatGPT: () -> Void

    @State private var isHovering = false

    /// Mouse travel (in window points) beyond which a click counts as a drag-scroll, not a copy.
    private static let clickTolerance: CGFloat = 4

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.text)
                    .font(.callout)
                    .lineLimit(3, reservesSpace: true)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Label {
                        Text(entry.date, format: .dateTime.hour().minute())
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                    if showsQuickActions {
                        Button(action: onOpenInChatGPT) {
                            Image("chatgpt-icon")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 13, height: 13)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Open in ChatGPT")
                        .accessibilityLabel("Open transcription in ChatGPT")
                    }
                }
            }

            Button(action: onCopy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .frame(width: 16, height: 16)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help(isCopied ? "Copied" : "Copy")
            .accessibilityLabel("Copy transcription")
        }
        .padding(10)
        .background(.quaternary.opacity(isHovering ? 0.7 : 0.4), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // The whole card copies on click. Measured in window space so content moving under
        // the pointer during a drag-scroll is not mistaken for a click.
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onEnded { value in
                    let distance = hypot(value.translation.width, value.translation.height)
                    if distance < Self.clickTolerance { onCopy() }
                }
        )
        .help("Click to copy")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onCopy() }
    }
}

#Preview {
    MenuBarPanelView(
        viewModel: TranscriptionViewModel(
            audioRecorder: AudioRecorder(),
            transcriptionService: WhisperTranscriptionService(),
            clipboard: ClipboardService(),
            historyStore: (try? SwiftDataHistoryStore(url: nil, legacyDefaults: nil)) ?? EmptyHistoryStore(),
            chatGPTLauncher: ChatGPTLauncherService(clipboard: ClipboardService())
        )
    )
    .environmentObject(AppSettings())
}
