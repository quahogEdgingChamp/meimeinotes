import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
struct MeimeiNotesApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let notes = NotesStore()
    private let timer = FocusTimer()
    private let cat = CatArtwork()
    private let chime = NSSound(named: "Glass")
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var exportDialog: NSSavePanel?
    private var hover = PanelHover()
    private var openPopovers: Set<PanelPopover> = []
    private var subscriptions: Set<AnyCancellable> = []
    private lazy var notifications: TimerNotifications? = {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return TimerNotifications { [weak self] in self?.openNotes() }
    }()
    private lazy var hotZone = HotZoneMonitor(onEnter: { [weak self] screen in
        guard let self else { return }
        if self.panel.isVisible, self.panel.isOnActiveSpace, self.panel.screen?.frame == screen.frame {
            self.panel.orderFrontRegardless()
        } else {
            self.showPanel(on: screen, focus: false, fromHotZone: true)
        }
    }, onPointer: { [weak self] pointer, atHotZone, time in
        self?.updatePanelHover(pointer: pointer, atHotZone: atHotZone, time: time)
    })
    private lazy var panel: NotesPanel = makePanel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        createStatusMenu()
        createMainMenu()
        watchState()
        openNotes()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openNotes()
        return false
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if panel.isVisible { positionPanel(on: panel.screen ?? preferredScreen) }
    }

    private var preferredScreen: NSScreen? {
        HotZoneMonitor.screen(at: NSEvent.mouseLocation) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func watchState() {
        preferences.$values.removeDuplicates().sink { [weak self] in
            self?.hotZone.apply($0)
        }.store(in: &subscriptions)

        timer.$secondsRemaining.combineLatest(timer.$countdown)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)

        timer.$countdown.combineLatest(preferences.$values.map(\.timerNotifications))
            .map { countdown, enabled in TimerNotificationPlan(enabled: enabled, countdown: countdown) }
            .removeDuplicates()
            .sink { [weak self] in self?.notifications?.apply($0) }
            .store(in: &subscriptions)

        timer.onFinish = { [weak self] in
            guard let self, self.preferences.values.timerSound else { return }
            if self.chime?.play() != true { NSSound.beep() }
        }
    }

    private func makePanel() -> NotesPanel {
        let panel = NotesPanel(contentRect: NSRect(x: 0, y: 0, width: 376, height: 464),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Meimei Notes"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.dismiss = { [weak self] in self?.dismissPanel() }
        panel.contentView = NSHostingView(rootView: PanelView(
            notes: notes, timer: timer, preferences: preferences, cat: cat,
            exportNotes: { [weak self] in self?.exportNotes() },
            openSettings: { [weak self] in self?.openSettings() },
            dismiss: { [weak self] in self?.dismissPanel() },
            popoverChanged: { [weak self] popover, shown in
                if shown { self?.openPopovers.insert(popover) } else { self?.openPopovers.remove(popover) }
            }
        ))
        return panel
    }

    private func positionPanel(on screen: NSScreen?) {
        guard let screen else { return }
        let point = preferences.values.triggerPoint
        panel.setFrameOrigin(point.panelOrigin(for: panel.frame.size, screen: screen.frame,
                                               visibleFrame: screen.visibleFrame))
    }

    private func showPanel(on screen: NSScreen?, focus: Bool, fromHotZone: Bool = false) {
        positionPanel(on: screen)
        hover = PanelHover(openedAtHotZone: fromHotZone)
        hotZone.trackPanel(true)
        if focus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func openNotes() {
        showPanel(on: panel.isVisible ? nil : preferredScreen, focus: true)
    }

    private func dismissPanel() {
        panel.orderOut(nil)
        hotZone.trackPanel(false)
        openPopovers.removeAll()
    }

    private func updatePanelHover(pointer: CGPoint, atHotZone: Bool, time: TimeInterval) {
        guard panel.isVisible else { return }
        let busy = NSEvent.pressedMouseButtons != 0 || RunLoop.main.currentMode == .eventTracking
            || exportDialog != nil || !openPopovers.isEmpty
        if hover.shouldDismiss(at: time, insidePanel: panel.frame.contains(pointer),
                              insideHotZone: atHotZone, interactionInProgress: busy) {
            dismissPanel()
        }
    }

    @objc private func exportNotes() {
        guard exportDialog == nil else { return }
        let dialog = NSSavePanel()
        dialog.title = "Export Notes"
        dialog.prompt = "Export"
        dialog.allowedContentTypes = [.json]
        dialog.nameFieldStringValue = "MeimeiNotes Backup.json"
        exportDialog = dialog

        NSApp.activate()
        dialog.begin { [weak self] response in
            guard let self else { return }
            defer { self.exportDialog = nil }
            guard response == .OK, let url = dialog.url else { return }
            do {
                try self.notes.export(to: url)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Couldn’t export notes"
                alert.runModal()
            }
        }
    }

    @objc private func openSettings() {
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Meimei Notes Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(preferences: preferences, cat: cat))
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func createStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        let menu = NSMenu()
        menu.addItem(command("Open Notes", #selector(openNotes)))
        menu.addItem(command("Export Notes…", #selector(exportNotes)))
        menu.addItem(command("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(command("Quit Meimei Notes", #selector(quit), key: "q"))
        item.menu = menu
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch timer.phase {
        case .running, .paused: symbol = "timer"
        case .finished: symbol = "bell.badge"
        case .ready: symbol = "note.text"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Meimei Notes")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        let showsTime = timer.phase == .running || timer.phase == .paused
        button.attributedTitle = NSAttributedString(
            string: showsTime ? " " + timer.display : "",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)]
        )
        button.toolTip = timer.phase == .finished ? "Meimei Notes · Time’s up" : "Meimei Notes"
    }

    private func createMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Meimei Notes")
        appMenu.addItem(command("Settings…", #selector(openSettings), key: ","))
        appMenu.addItem(command("Quit Meimei Notes", #selector(quit), key: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func command(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

private final class NotesPanel: NSPanel {
    var dismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { dismiss?() }
}
