import AppKit
import SwiftUI
import ClaudePulseCore

/// The three visual states of the command bar.
enum CommandBarState: Equatable {
    case strip
    case preview
    case dashboard
}

/// A floating, non-activating panel that hosts the command bar UI.
final class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }
}

/// Manages the command bar window lifecycle and state transitions.
@MainActor
final class CommandBarController: ObservableObject {
    let panel: CommandBarPanel
    @Published var barState: CommandBarState = .strip
    private let layout: ScreenLayout
    private var clickMonitor: Any?
    private var autoCollapseTask: Task<Void, Never>?

    init(appState: AppState, sessionManager: SessionManager) {
        self.layout = ScreenLayout()
        self.panel = CommandBarPanel()

        let rootView = CommandBarRootView(
            appState: appState,
            sessionManager: sessionManager,
            controller: self
        )
        let hostView = NSHostingView(rootView: rootView)
        hostView.frame = panel.contentView?.bounds ?? .zero
        hostView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostView)

        applyFrame(for: .strip, animated: false)

        // Listen for session events to auto-expand
        NotificationCenter.default.addObserver(
            forName: SessionManager.sessionEventNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?["event"] as? String else { return }
            if event == SessionManager.SessionEvent.permissionRequested.rawValue ||
               event == SessionManager.SessionEvent.questionAsked.rawValue {
                self?.expandToPreview()
            }
        }
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func toggle() {
        switch barState {
        case .strip:
            transition(to: .dashboard)
        case .preview, .dashboard:
            transition(to: .strip)
        }
    }

    func expandToPreview() {
        guard barState == .strip else { return }
        transition(to: .preview)
        scheduleAutoCollapse(after: 5)
    }

    func expandToDashboard() {
        transition(to: .dashboard)
    }

    func collapse() {
        transition(to: .strip)
    }

    func transition(to newState: CommandBarState) {
        autoCollapseTask?.cancel()
        barState = newState
        applyFrame(for: newState, animated: true)

        if newState == .dashboard {
            startClickOutsideMonitor()
        } else {
            stopClickOutsideMonitor()
        }
    }

    private func applyFrame(for state: CommandBarState, animated: Bool) {
        let frame: NSRect
        switch state {
        case .strip:     frame = layout.stripFrame()
        case .preview:   frame = layout.previewFrame()
        case .dashboard: frame = layout.dashboardFrame()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func scheduleAutoCollapse(after seconds: TimeInterval) {
        autoCollapseTask?.cancel()
        autoCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled && barState == .preview {
                collapse()
            }
        }
    }

    private func startClickOutsideMonitor() {
        stopClickOutsideMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let screenLoc = NSEvent.mouseLocation
            if !self.panel.frame.contains(screenLoc) {
                Task { @MainActor in self.collapse() }
            }
        }
    }

    private func stopClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    deinit {
        stopClickOutsideMonitor()
    }
}
