import SwiftUI
import ClaudePulseCore

/// Root view that switches between the three command bar states.
struct CommandBarRootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var sessionManager: SessionManager
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var controller: CommandBarController

    var body: some View {
        Group {
            switch controller.barState {
            case .strip:
                CommandBarStripView(appState: appState, sessionManager: sessionManager)
                    .onTapGesture { controller.expandToDashboard() }

            case .preview:
                CommandBarPreviewView(
                    sessionManager: sessionManager,
                    onExpand: { controller.expandToDashboard() },
                    onCollapse: { controller.collapse() }
                )

            case .dashboard:
                CommandBarDashboardView(
                    appState: appState,
                    sessionManager: sessionManager,
                    updateManager: updateManager,
                    onCollapse: { controller.collapse() },
                    onJumpToTerminal: { session in
                        TerminalJumper.jump(to: session)
                    }
                )
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: controller.barState)
    }
}
