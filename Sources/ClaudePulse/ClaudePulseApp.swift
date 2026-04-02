import SwiftUI
import AppKit
import ClaudePulseCore

@main
struct ClaudePulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Invisible settings window — the real UI is the command bar panel
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var sessionManager: SessionManager!
    private var commandBar: CommandBarController!
    private var socketServer: SocketServer?
    private var logWatcher: LogWatcher?
    private var soundManager: SoundManager?
    private var updateManager: UpdateManager!
    private var hotKeyMonitor: Any?
    private var statusItem: NSStatusItem?
    private var pruneTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — this is a background utility with a status bar item
        NSApp.setActivationPolicy(.accessory)

        // Auto-configure Claude Code hooks on first launch (and update on every launch)
        HookInstaller.installIfNeeded()

        appState = AppState()
        sessionManager = SessionManager()
        updateManager = UpdateManager()

        // Start the command bar
        commandBar = CommandBarController(appState: appState, sessionManager: sessionManager, updateManager: updateManager)
        commandBar.show()

        // Start usage monitoring
        appState.start()

        // Start socket server for real-time agent detection
        startSocketServer()

        // Start log watcher for fallback detection
        startLogWatcher()

        // Initialize sound effects
        soundManager = SoundManager(sessionManager: sessionManager)

        // Check for updates silently on launch
        updateManager.checkSilently()

        // Add a minimal status bar item as a fallback way to quit
        setupStatusItem()

        // Register global hotkey (Cmd+Shift+P)
        registerHotKey()

        // Prune stale sessions every 10 minutes
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sessionManager.pruneStale(olderThan: 1800) // 30 min
            }
        }
    }

    private func startSocketServer() {
        do {
            socketServer = try SocketServer(sessionManager: sessionManager)
            socketServer?.start()
        } catch {
            print("[ClaudePulse] Socket server failed to start: \(error)")
        }
    }

    private func startLogWatcher() {
        logWatcher = LogWatcher(sessionManager: sessionManager)
        logWatcher?.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Claude Pulse")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Command Bar", action: #selector(toggleCommandBar), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates...", action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claude Pulse", action: #selector(quitApp), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    @objc private func toggleCommandBar() {
        commandBar.toggle()
    }

    @objc private func checkUpdates() {
        updateManager.checkForUpdates()
        commandBar.expandToDashboard()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func registerHotKey() {
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Cmd+Shift+P
            if event.modifierFlags.contains([.command, .shift]) && event.keyCode == 35 {
                Task { @MainActor in
                    self?.commandBar.toggle()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pruneTimer?.invalidate()
        soundManager?.tearDown()
        socketServer?.stop()
        logWatcher?.stop()
        if let monitor = hotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
