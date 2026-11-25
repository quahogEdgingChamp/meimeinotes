import SwiftUI

// Select the property wrapper on SDKs that also ship a State macro.
typealias ViewState<Value> = State<Value>

enum PanelPopover: Hashable {
    case customDuration, deleteNote
}

struct PanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let notes: NotesStore
    let timer: FocusTimer
    let stopwatch: Stopwatch
    @ObservedObject var preferences: Preferences
    @ObservedObject var cat: CatArtwork
    let exportNotes: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void
    let popoverChanged: (PanelPopover, Bool) -> Void

    var body: some View {
        let palette = Palette(isDark: colorScheme == .dark, showsCat: preferences.values.catEnabled)
        VStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "note.text")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 31, height: 31)
                    .background(palette.selection, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)

                Text("Meimei Notes")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                IconButton("Export Notes…", symbol: "square.and.arrow.up", action: exportNotes)
                IconButton("Settings", symbol: "gearshape", action: openSettings)
                IconButton("Close Panel", symbol: "xmark", action: dismiss)
            }

            TimerCard(timer: timer, stopwatch: stopwatch, mode: $preferences.values.clockMode, palette: palette) {
                popoverChanged(.customDuration, $0)
            }
            NotesPane(notes: notes, portrait: palette.showsCat ? cat.portrait : nil, palette: palette) {
                popoverChanged(.deleteNote, $0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.surface)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(palette.border).allowsHitTesting(false)
        }
        .tint(palette.accent)
        .onExitCommand(perform: dismiss)
    }
}

private struct TimerCard: View {
    @ObservedObject var timer: FocusTimer
    @ObservedObject var stopwatch: Stopwatch
    @Binding var mode: ClockMode
    let palette: Palette
    let popoverChanged: (Bool) -> Void

    @ViewState private var editingDuration = false
    @ViewState private var minutes = ""
    @ViewState private var seconds = ""

    var body: some View {
        VStack(alignment: .leading, spacing: palette.showsCat ? 8 : 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        ModeSwitch(mode: $mode, running: runningModes, palette: palette)
                        if let status {
                            Text(status)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isFinished ? palette.accent : .secondary)
                        }
                    }

                    Text(mode == .timer ? timer.display : stopwatch.display)
                        .font(.system(size: 43, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel(mode == .timer ? "Time remaining" : "Time elapsed")
                        .accessibilityValue(spokenTime)
                }

                Spacer()
                clockActions
            }
            .frame(height: palette.showsCat ? 72 : 77)

            if mode == .timer {
                presets

                GeometryReader { proxy in
                    Capsule().fill(palette.selection)
                    Capsule().fill(palette.accent)
                        .frame(width: proxy.size.width * timer.progress)
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
        }
        .padding(palette.showsCat ? 11 : 13)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15).strokeBorder(palette.border).allowsHitTesting(false)
        }
        .onChange(of: editingDuration) { _, shown in popoverChanged(shown) }
        .onChange(of: mode) { _, _ in editingDuration = false }
    }

    private var presets: some View {
        HStack(spacing: 5) {
            ForEach(FocusTimer.presets, id: \.self) { preset in
                let isSelected = timer.countdown.duration == preset * 60
                Button("\(preset)m") { timer.setDuration(preset * 60) }
                    .buttonStyle(ChipStyle(
                        foreground: isSelected ? palette.accent : .secondary,
                        background: isSelected ? palette.selection : palette.control
                    ))
                    .help("Set a \(preset)-minute timer")
                    .accessibilityLabel("\(preset) minutes")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
            }

            Button("Custom…") {
                minutes = String(timer.countdown.duration / 60)
                seconds = String(timer.countdown.duration % 60)
                editingDuration = true
            }
            .buttonStyle(ChipStyle(foreground: .secondary, background: palette.control))
            .help("Set a custom timer duration")
            .popover(isPresented: $editingDuration, arrowEdge: .bottom) { durationEditor }

            Spacer(minLength: 1)
        }
    }

    private var clockActions: some View {
        HStack(spacing: 6) {
            IconButton("Reset \(mode.title)", symbol: "arrow.counterclockwise", background: palette.control) {
                if mode == .timer { timer.reset() } else { stopwatch.reset() }
            }
            .disabled(!canReset)
            .opacity(canReset ? 1 : 0.48)

            IconButton(playLabel, symbol: isRunning ? "pause.fill" : "play.fill",
                       foreground: palette.onAction, background: palette.action, width: 35) {
                if mode == .timer { timer.toggle() } else { stopwatch.toggle() }
            }
        }
    }

    private var runningModes: Set<ClockMode> {
        var modes: Set<ClockMode> = []
        if timer.phase == .running { modes.insert(.timer) }
        if stopwatch.phase == .running { modes.insert(.stopwatch) }
        return modes
    }

    private var isRunning: Bool { runningModes.contains(mode) }
    private var isPaused: Bool { mode == .timer ? timer.phase == .paused : stopwatch.phase == .paused }
    private var isFinished: Bool { mode == .timer && timer.phase == .finished }
    private var canReset: Bool { mode == .timer ? timer.phase != .ready : stopwatch.phase != .ready }

    private var playLabel: String {
        if isRunning { return "Pause \(mode.title)" }
        return isPaused ? "Resume \(mode.title)" : "Start \(mode.title)"
    }

    private var status: String? {
        if isPaused { return "Paused" }
        return isFinished ? "Time’s up" : nil
    }

    private var spokenTime: String {
        let total = mode == .timer ? timer.secondsRemaining : stopwatch.secondsElapsed
        // The countdown reads as minutes up to 99, matching its display.
        let hours = mode == .stopwatch ? total / 3600 : 0
        return (hours > 0 ? "\(hours) hours, " : "") + "\(total / 60 - hours * 60) minutes, \(total % 60) seconds"
    }

    private var chosenDuration: Int? {
        let m = minutes.trimmingCharacters(in: .whitespaces)
        let s = seconds.trimmingCharacters(in: .whitespaces)
        guard let mins = Int(m.isEmpty ? "0" : m), (0...99).contains(mins),
              let secs = Int(s.isEmpty ? "0" : s), (0...59).contains(secs),
              mins + secs > 0 else { return nil }
        return mins * 60 + secs
    }

    private var durationEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Duration").font(.headline)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minutes").font(.caption).foregroundStyle(.secondary)
                    TextField("Minutes", text: $minutes).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seconds").font(.caption).foregroundStyle(.secondary)
                    TextField("Seconds", text: $seconds).labelsHidden()
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { editingDuration = false }.keyboardShortcut(.cancelAction)
                Button("Set Timer") {
                    if let chosenDuration { timer.setDuration(chosenDuration) }
                    editingDuration = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosenDuration == nil)
            }
        }
        .padding(15)
        .frame(width: 220)
    }
}

private struct NotesPane: View {
    @ObservedObject var notes: NotesStore
    let portrait: CatPortrait?
    let palette: Palette
    let popoverChanged: (Bool) -> Void
    @ViewState private var confirmingDelete = false
    @ViewState private var browsing = false
    @ViewState private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        let note = notes.current

        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Button {
                    confirmingDelete = false
                    browsing.toggle()
                    if browsing { search = "" }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: browsing ? "chevron.left" : "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Text(browsing ? "Back to note" : note.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 27)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(browsing ? "Return to the editor" : "Search and switch notes")
                .accessibilityLabel(browsing ? "Back to Note" : "Search and Switch Notes")
                .accessibilityValue(note.title)

                if !browsing {
                    IconButton(note.isPinned ? "Unpin Note" : "Pin Note", symbol: note.isPinned ? "pin.fill" : "pin",
                               foreground: note.isPinned ? palette.accent : .secondary) { notes.togglePin(note.id) }
                }

                IconButton("New Note", symbol: "plus", background: palette.control) {
                    confirmingDelete = false
                    notes.create()
                    browsing = false
                }
                if !browsing {
                    IconButton("Delete Note", symbol: "trash") { confirmingDelete = true }
                        .popover(isPresented: $confirmingDelete, arrowEdge: .bottom) {
                            deleteConfirmation(for: note)
                        }
                }
            }

            if browsing {
                noteBrowser
            } else {
                noteEditor(for: note)
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: confirmingDelete) { _, shown in popoverChanged(shown) }
    }

    private var noteBrowser: some View {
        let matches = notes.matching(search)

        return VStack(spacing: 7) {
            TextField("Search notes…", text: $search)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onAppear { searchFocused = true }
                .onSubmit {
                    if let first = matches.first { open(first) }
                }

            if matches.isEmpty {
                Text("No matching notes")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(matches) { note in
                            let isCurrent = notes.current.id == note.id
                            Button { open(note) } label: {
                                HStack(spacing: 7) {
                                    if note.isPinned {
                                        Image(systemName: "pin.fill").foregroundStyle(palette.accent)
                                    }
                                    Text(note.title).lineLimit(1)
                                    Spacer(minLength: 6)
                                    if isCurrent {
                                        Image(systemName: "checkmark").foregroundStyle(palette.accent)
                                    }
                                }
                                .font(.system(size: 13))
                                .padding(7)
                                .background(isCurrent ? palette.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(note.title)
                            .accessibilityValue(note.isPinned ? "Pinned" : "")
                            .accessibilityAddTraits(isCurrent ? .isSelected : [])
                        }
                    }
                    .padding(2)
                }
            }
        }
        .padding(8)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border).allowsHitTesting(false)
        }
    }

    private func open(_ note: Note) {
        notes.select(note.id)
        browsing = false
    }

    private func noteEditor(for note: Note) -> some View {
        GeometryReader { geometry in
            let portraitHeight = min(184, geometry.size.height - 142)

            VStack(spacing: 0) {
                if let portrait, portraitHeight >= 74 {
                    CatNoteHeader(portrait: portrait, palette: palette)
                        .frame(height: portraitHeight)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                editor(for: note)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.paper)
            .clipShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border).allowsHitTesting(false)
            }
        }
    }

    private func editor(for note: Note) -> some View {
        TextEditor(text: Binding(get: { notes.text(for: note.id) }, set: { notes.update(note.id, text: $0) }))
            .id(note.id)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(8)
            .accessibilityLabel("Note text")
            .overlay(alignment: .topLeading) {
                if note.text.isEmpty {
                    Text("Write a note…")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 13)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    private func deleteConfirmation(for note: Note) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete “\(note.title)”?").font(.headline)
            HStack {
                Spacer()
                Button("Cancel") { confirmingDelete = false }.keyboardShortcut(.cancelAction)
                Button("Delete", role: .destructive) {
                    notes.delete(note.id)
                    confirmingDelete = false
                }
            }
        }
        .padding(15)
        .frame(width: 235)
    }
}

private struct ModeSwitch: View {
    @Binding var mode: ClockMode
    let running: Set<ClockMode>
    let palette: Palette

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ClockMode.allCases) { option in
                let isSelected = mode == option
                Button { mode = option } label: {
                    HStack(spacing: 4) {
                        Text(option.title)
                        if !isSelected && running.contains(option) {
                            Circle().fill(palette.accent).frame(width: 5, height: 5)
                        }
                    }
                }
                .buttonStyle(ChipStyle(foreground: isSelected ? palette.accent : .secondary,
                                       background: isSelected ? palette.selection : .clear,
                                       horizontalPadding: 7, height: 16, cornerRadius: 5))
                .help(option == .timer ? "Count down from a set time" : "Count up from zero")
                .accessibilityLabel(option.title)
                .accessibilityValue(running.contains(option) ? "Running" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(palette.control, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct IconButton: View {
    let label: String
    let symbol: String
    var foreground: Color = .secondary
    var background: Color = .clear
    var width: CGFloat = 27
    let action: () -> Void

    init(_ label: String, symbol: String, foreground: Color = .secondary, background: Color = .clear,
         width: CGFloat = 27, action: @escaping () -> Void) {
        self.label = label
        self.symbol = symbol
        self.foreground = foreground
        self.background = background
        self.width = width
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: width, height: 27)
        }
        .buttonStyle(ChipStyle(foreground: foreground, background: background, horizontalPadding: 0))
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct ChipStyle: ButtonStyle {
    let foreground: Color
    let background: Color
    var horizontalPadding: CGFloat = 8
    var height: CGFloat = 24
    var cornerRadius: CGFloat = 7

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: height)
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(.primary.opacity(0.10))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct Palette {
    let isDark: Bool
    let showsCat: Bool

    var surface: Color { showsCat ? color(0xfff6f0, 0x281f20) : color(0xf4f5f7, 0x202328) }
    var card: Color { showsCat ? color(0xffeadd, 0x3b2929) : color(0xffffff, 0x2b2e34) }
    var paper: Color { showsCat ? color(0xfffcf9, 0x312526) : color(0xffffff, 0x272a30) }
    var portraitBackdrop: Color { color(0xf4d9c5, 0x513831) }
    var portraitHighlight: Color { color(0xfff3e4, 0x735044) }
    var portraitMat: Color { color(0xecd0bf, 0x402d28) }
    var accent: Color { showsCat ? color(0x9b472f, 0xffb497) : color(0x4354a0, 0xb4bfff) }
    var action: Color { showsCat ? color(0x9b472f, 0xffb497) : color(0x4656a6, 0xb4bfff) }
    var onAction: Color { isDark ? .black : .white }
    var border: Color { isDark ? .white.opacity(0.12) : .black.opacity(0.095) }
    var control: Color { isDark ? .white.opacity(0.08) : .black.opacity(0.055) }
    var selection: Color { accent.opacity(isDark ? 0.17 : 0.11) }

    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        let rgb = isDark ? dark : light
        return Color(red: Double((rgb >> 16) & 255) / 255,
                     green: Double((rgb >> 8) & 255) / 255,
                     blue: Double(rgb & 255) / 255)
    }
}

