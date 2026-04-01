import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Activates the correct terminal window/tab for a given agent session.
public enum TerminalJumper {

    /// Jump to the terminal associated with the given session.
    @MainActor
    public static func jump(to session: AgentSession) {
        guard let info = session.terminalInfo else {
            // No terminal info — try to find by PID if we have a conversation path
            print("[ClaudePulse] No terminal info for session \(session.id)")
            return
        }

        #if canImport(AppKit)
        // Try PID-based activation first
        if let pid = info.pid {
            if activateByPID(pid) { return }
        }

        // Try bundle identifier
        if let bundleId = info.bundleIdentifier {
            if activateByBundleId(bundleId, windowID: info.windowID) { return }
        }

        // Fallback: AppleScript for common terminals
        if let tty = info.tty {
            activateByTTY(tty)
        }
        #endif
    }

    #if canImport(AppKit)
    /// Activate the app that owns the given PID.
    private static func activateByPID(_ pid: Int32) -> Bool {
        // Find the parent terminal process
        let terminalPID = findTerminalParent(pid: pid)
        guard let app = NSRunningApplication(processIdentifier: terminalPID ?? pid) else { return false }
        return app.activate()
    }

    /// Activate an app by bundle identifier and optionally raise a specific window.
    private static func activateByBundleId(_ bundleId: String, windowID: UInt32?) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return false
        }
        return app.activate()
    }

    /// Use AppleScript to activate a terminal by TTY path.
    private static func activateByTTY(_ tty: String) {
        // Try iTerm2 first
        let iterm = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select s
                                select t
                                set index of w to 1
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """

        // Try Terminal.app
        let terminal = """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """

        // Try iTerm2 first, then Terminal.app
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first != nil {
            runAppleScript(iterm)
        } else if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first != nil {
            runAppleScript(terminal)
        }
    }

    /// Find the terminal process that is the parent of the given PID.
    private static func findTerminalParent(pid: Int32) -> Int32? {
        let knownTerminals: Set<String> = [
            "Terminal", "iTerm2", "Alacritty", "kitty", "WarpTerminal",
            "Ghostty", "Code", "Cursor"
        ]

        var currentPID = pid
        for _ in 0..<20 { // max depth to prevent infinite loops
            guard let app = NSRunningApplication(processIdentifier: currentPID) else { break }
            let name = app.localizedName ?? ""
            if knownTerminals.contains(name) || name.contains("Terminal") {
                return currentPID
            }
            // Get parent PID via sysctl
            var kinfo = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, currentPID]
            guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0 else { break }
            let parentPID = kinfo.kp_eproc.e_ppid
            if parentPID <= 1 || parentPID == currentPID { break }
            currentPID = parentPID
        }
        return nil
    }

    private static func runAppleScript(_ source: String) {
        guard let script = NSAppleScript(source: source) else { return }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }
    #endif
}
