import AppKit

/// Computes the position and size for the floating command bar on any display.
struct ScreenLayout {
    let screenFrame: NSRect
    let visibleFrame: NSRect
    let hasNotch: Bool

    init(screen: NSScreen? = NSScreen.main) {
        let resolved = screen ?? NSScreen.screens.first ?? NSScreen.main
        self.screenFrame = resolved?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        self.visibleFrame = resolved?.visibleFrame ?? self.screenFrame
        self.hasNotch = (screenFrame.maxY - visibleFrame.maxY) > 24
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
