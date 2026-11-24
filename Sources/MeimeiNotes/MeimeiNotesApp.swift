import AppKit
import Combine
import SwiftUI

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
    private var subscriptions: Set<AnyCancellable> = []
    private lazy var hotZone = HotZoneMonitor { [weak self] screen in
        guard let self, !self.panel.isVisible || self.panel.screen?.frame != screen.frame else { return }
        self.showPanel(on: screen, focus: false)
    }
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
        panel.contentView = NSHostingView(rootView: PanelView(
            notes: notes, timer: timer, preferences: preferences, cat: cat,
            openSettings: { [weak self] in self?.openSettings() },
            dismiss: { [weak self] in self?.panel.orderOut(nil) }
        ))
        return panel
    }

    private func positionPanel(on screen: NSScreen?) {
        guard let screen else { return }
        let point = preferences.values.triggerPoint
        panel.setFrameOrigin(point.panelOrigin(for: panel.frame.size, screen: screen.frame,
                                               visibleFrame: screen.visibleFrame))
    }

    private func showPanel(on screen: NSScreen?, focus: Bool) {
        positionPanel(on: screen)
        if focus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func openNotes() {
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        } else {
            showPanel(on: preferredScreen, focus: true)
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
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}
