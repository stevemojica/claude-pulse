import AppKit

/// Computes the position and size for the floating command bar on any display.
struct ScreenLayout {
    let screenFrame: NSRect
    let visibleFrame: NSRect
    let hasNotch: Bool

    init(screen: NSScreen? = NSScreen.main) {
        let screen = screen ?? NSScreen.screens.first!
        self.screenFrame = screen.frame
        self.visibleFrame = screen.visibleFrame
        // On notch MacBooks, the visible frame top is lower than the screen frame top
        self.hasNotch = (screen.frame.maxY - screen.visibleFrame.maxY) > 24
    }

    /// Frame for the collapsed strip state.
    func stripFrame(width: CGFloat = 300, height: CGFloat = 32) -> NSRect {
        let x = screenFrame.midX - width / 2
        let y = visibleFrame.maxY - height - 4
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Frame for the preview (medium expansion) state.
    func previewFrame(width: CGFloat = 320, height: CGFloat = 100) -> NSRect {
        let x = screenFrame.midX - width / 2
        let y = visibleFrame.maxY - height - 4
        return NSRect(x: x, y: y, width: width, height: height)
    }

    /// Frame for the full dashboard state.
    func dashboardFrame(width: CGFloat = 380, height: CGFloat = 520) -> NSRect {
        let x = screenFrame.midX - width / 2
        let y = visibleFrame.maxY - height - 4
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
