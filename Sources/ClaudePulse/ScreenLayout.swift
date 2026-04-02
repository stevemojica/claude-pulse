import AppKit

/// Position preference for the command bar.
enum BarPosition: String, CaseIterable {
    case top
    case bottom
}

/// Computes the position and size for the floating command bar on any display.
struct ScreenLayout {
    let screenFrame: NSRect
    let visibleFrame: NSRect
    let hasNotch: Bool
    let position: BarPosition

    init(screen: NSScreen? = NSScreen.main, position: BarPosition = .bottom) {
        let resolved = screen ?? NSScreen.screens.first ?? NSScreen.main
        self.screenFrame = resolved?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        self.visibleFrame = resolved?.visibleFrame ?? self.screenFrame
        self.hasNotch = (screenFrame.maxY - visibleFrame.maxY) > 24
        self.position = position
    }

    /// Frame for the collapsed strip state.
    func stripFrame(width: CGFloat = 300, height: CGFloat = 32) -> NSRect {
        let x = screenFrame.midX - width / 2
        let y = yOrigin(height: height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Frame for the preview (medium expansion) state.
    func previewFrame(width: CGFloat = 320, height: CGFloat = 100) -> NSRect {
        let x = screenFrame.midX - width / 2
        let y = yOrigin(height: height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Frame for the full dashboard state.
    func dashboardFrame(width: CGFloat = 380, height: CGFloat = 520) -> NSRect {
        let x = screenFrame.midX - width / 2
        let y = yOrigin(height: height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Compute Y origin based on position preference.
    /// Top: anchors strip/preview at the top of visible frame; dashboard drops down from there.
    /// Bottom: anchors at the bottom of visible frame (current behavior).
    private func yOrigin(height: CGFloat) -> CGFloat {
        switch position {
        case .top:
            // Place just below the menu bar (or notch on notched displays)
            return visibleFrame.maxY - height - 4
        case .bottom:
            // Place just above the Dock / bottom of visible frame
            return visibleFrame.minY + 4
        }
    }
}
