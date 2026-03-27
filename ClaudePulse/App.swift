import SwiftUI

@main
struct ClaudePulseApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        MenuBarExtra {
            DashboardView(state: state)
                .task {
                    state.start()
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                if state.started {
                    Text("\(Int(state.fiveHourPct))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
