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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var sessionManager: SessionManager!
    private var commandBar: CommandBarController!
    private var socketServer: SocketServer?
    private var logWatcher: LogWatcher?
    private var soundManager: SoundManager?
    private var hotKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — this is a background utility
        NSApp.setActivationPolicy(.accessory)

        appState = AppState()
        sessionManager = SessionManager()

        // Start the command bar
        commandBar = CommandBarController(appState: appState, sessionManager: sessionManager)
        commandBar.show()

        // Start usage monitoring
        appState.start()

        // Start socket server for real-time agent detection
        startSocketServer()

        // Start log watcher for fallback detection
        startLogWatcher()

        // Initialize sound effects
        soundManager = SoundManager(sessionManager: sessionManager)

        // Register global hotkey (Cmd+Shift+P)
        registerHotKey()
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
        socketServer?.stop()
        logWatcher?.stop()
        if let monitor = hotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
