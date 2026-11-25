import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var preferences: Preferences
    @ObservedObject var cat: CatArtwork
    @ViewState private var choosingFile = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            catSettings
                .tabItem { Label("Cat Mode", systemImage: "pawprint") }
        }
        .padding(16)
        .frame(width: 420, height: 420)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url): cat.importImage(at: url)
            case .failure(let error): cat.errorMessage = error.localizedDescription
            }
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle("Open when the pointer enters a hot zone", isOn: $preferences.values.hotZoneEnabled)

            VStack(alignment: .leading, spacing: 9) {
                Picker("Trigger location", selection: $preferences.values.triggerLocation) {
                    ForEach(TriggerLocation.allCases) { location in Text(location.title).tag(location) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                DisplayMap(point: preferences.values.triggerPoint, isCustom: isCustomSpot) { point in
                    preferences.values.customPoint = point
                }
                .frame(height: 112)

                if isCustomSpot {
                    HStack(spacing: 14) {
                        Slider(value: $preferences.values.customPoint.x, in: 0...1) { Text("Across") }
                        Slider(value: $preferences.values.customPoint.y, in: 0...1) { Text("Down") }
                    }
                }

                Text(isCustomSpot ? "Click the display to place the hot zone. For a spot behind the camera notch, pause just below it."
                     : "Pause briefly in the marked corner to open the panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!preferences.values.hotZoneEnabled)

            Divider()

            Toggle("Show a notification when the timer ends", isOn: $preferences.values.timerNotifications)
            Toggle("Play a sound when the timer ends", isOn: $preferences.values.timerSound)
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var isCustomSpot: Bool { preferences.values.triggerLocation == .custom }

    private var catSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Show a cat on the note", isOn: $preferences.values.catEnabled)

            if preferences.values.catEnabled {
                if let portrait = cat.portrait {
                    let palette = Palette(isDark: colorScheme == .dark, showsCat: true)
                    CatNoteHeader(portrait: portrait, palette: palette)
                        .frame(height: 158)
                        .padding(.bottom, 12)
                        .background(palette.paper)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border).allowsHitTesting(false)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Cat preview")
                }

                HStack {
                    Button("Choose Cat Image…") { choosingFile = true }
                    if cat.hasCustomImage {
                        Button("Use Starter Cat") { cat.restoreStarter() }
                    }
                }
                .disabled(cat.isPreparing)

                if cat.canRemoveBackground {
                    Toggle("Remove photo background", isOn: Binding(
                        get: { cat.removesBackground }, set: { cat.setRemovesBackground($0) }
                    ))
                    .disabled(cat.isPreparing)
                }

                if cat.isPreparing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Preparing cat…").foregroundStyle(.secondary)
                    }
                } else if let message = cat.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

private struct DisplayMap: View {
    let point: TriggerPoint
    let isCustom: Bool
    let choosePoint: (TriggerPoint) -> Void

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 10
            let width = proxy.size.width - 2 * inset
            let height = proxy.size.height - 2 * inset

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.15))

                if isCustom {
                    Path { path in
                        let centerX = proxy.size.width / 2
                        let centerY = proxy.size.height / 2
                        path.move(to: CGPoint(x: inset, y: centerY))
                        path.addLine(to: CGPoint(x: inset + width, y: centerY))
                        path.move(to: CGPoint(x: centerX, y: inset))
                        path.addLine(to: CGPoint(x: centerX, y: inset + height))
                    }
                    .stroke(.secondary.opacity(0.30), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }

                Circle().fill(.tint)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                    .frame(width: 14, height: 14)
                    .position(x: inset + width * point.x, y: inset + height * point.y)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isCustom, width > 0, height > 0 else { return }
                choosePoint(TriggerPoint(
                    x: min(1, max(0, (drag.location.x - inset) / width)),
                    y: min(1, max(0, (drag.location.y - inset) / height))
                ))
            })
        }
        .accessibilityHidden(true)
    }
}
