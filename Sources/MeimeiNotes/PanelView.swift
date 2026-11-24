import SwiftUI

// Select the property wrapper on SDKs that also ship a State macro.
typealias ViewState<Value> = State<Value>

struct PanelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let notes: NotesStore
    let timer: FocusTimer
    @ObservedObject var preferences: Preferences
    @ObservedObject var cat: CatArtwork
    let openSettings: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let palette = Palette(isDark: colorScheme == .dark, showsCat: preferences.values.catEnabled)
        VStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: palette.showsCat ? "pawprint.fill" : "note.text")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 31, height: 31)
                    .background(palette.selection, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)

                Text("Meimei Notes")
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                IconButton("Settings", symbol: "gearshape", action: openSettings)
                IconButton("Close Panel", symbol: "xmark", action: dismiss)
            }

            TimerCard(timer: timer, cat: cat.image, palette: palette)
            NotesPane(notes: notes, palette: palette)
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
    let cat: NSImage?
    let palette: Palette

    @ViewState private var editingDuration = false
    @ViewState private var minutes = ""
    @ViewState private var seconds = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(status)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(timer.phase == .finished ? palette.accent : .secondary)

                    Text(timer.display)
                        .font(.system(size: 43, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .accessibilityLabel("Time remaining")
                        .accessibilityValue("\(timer.secondsRemaining / 60) minutes, \(timer.secondsRemaining % 60) seconds")
                }

                Spacer()

                if palette.showsCat, let cat {
                    Image(nsImage: cat)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 145, height: 104)
                        .accessibilityHidden(true)
                } else {
                    timerActions
                }
            }
            .frame(height: palette.showsCat && cat != nil ? 104 : 77)

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

                if palette.showsCat, cat != nil { timerActions }
            }

            GeometryReader { proxy in
                Capsule().fill(palette.selection)
                Capsule().fill(palette.accent)
                    .frame(width: proxy.size.width * timer.progress)
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .padding(13)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15).strokeBorder(palette.border).allowsHitTesting(false)
        }
    }

    private var timerActions: some View {
        HStack(spacing: 6) {
            IconButton("Reset Timer", symbol: "arrow.counterclockwise", background: palette.control) { timer.reset() }
                .disabled(timer.phase == .ready)
                .opacity(timer.phase == .ready ? 0.48 : 1)

            IconButton(playLabel, symbol: timer.phase == .running ? "pause.fill" : "play.fill",
                       foreground: palette.onAction, background: palette.action, width: 35) { timer.toggle() }
        }
    }

    private var playLabel: String {
        switch timer.phase {
        case .running: "Pause Timer"
        case .paused: "Resume Timer"
        case .ready, .finished: "Start Timer"
        }
    }

    private var status: String {
        switch timer.phase {
        case .ready, .running: "Timer"
        case .paused: "Paused"
        case .finished: "Time’s up"
        }
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
    let palette: Palette
    @ViewState private var confirmingDelete = false

    var body: some View {
        let note = notes.current

        VStack(spacing: 7) {
            HStack(spacing: 5) {
                Menu {
                    Picker("Note", selection: Binding(get: { notes.current.id }, set: notes.select)) {
                        ForEach(notes.notes) { item in Text(item.title).tag(item.id) }
                    }
                } label: {
                    Text(note.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 230, alignment: .leading)
                .help("Switch notes")
                .accessibilityLabel("Switch Notes")
                .accessibilityValue(note.title)

                Spacer(minLength: 5)

                IconButton("New Note", symbol: "plus", background: palette.control) { notes.create() }
                IconButton("Delete Note", symbol: "trash") { confirmingDelete = true }
                    .popover(isPresented: $confirmingDelete, arrowEdge: .bottom) {
                        deleteConfirmation(for: note)
                    }
            }

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
                .background(palette.paper, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border).allowsHitTesting(false)
                }
        }
        .frame(maxHeight: .infinity)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(minHeight: 24)
            .background(background, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.10))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct Palette {
    let isDark: Bool
    let showsCat: Bool

    var surface: Color { showsCat ? color(0xfff6f0, 0x281f20) : color(0xf4f5f7, 0x202328) }
    var card: Color { showsCat ? color(0xffeadd, 0x3b2929) : color(0xffffff, 0x2b2e34) }
    var paper: Color { showsCat ? color(0xfffcf9, 0x312526) : color(0xffffff, 0x272a30) }
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

