import AppKit

final class BrowserWindowController: NSWindowController {
    private let viewController: BrowserViewController

    init(client: BridgeClient, port: UInt16) {
        viewController = BrowserViewController(client: client)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pharo System Browser (port \(port))"
        window.contentViewController = viewController
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PharoNativeBrowser.MainWindow")
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func loadInitialContent() {
        viewController.loadPackages()
    }
}
