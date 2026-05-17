import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let port: UInt16
    private var windowControllers: [BrowserWindowController] = []
    private var menuController: AppMenuController?

    init(port: UInt16) {
        self.port = port
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = AppMenuController()
        menuController?.install()

        openNewBrowserWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @objc func openNewBrowserWindow() {
        guard port != 0 else {
            presentPortError()
            return
        }
        let client = BridgeClient(host: "127.0.0.1", port: port)
        let wc = BrowserWindowController(client: client, port: port)
        wc.window?.delegate = self
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        windowControllers.append(wc)
        wc.loadInitialContent()
    }

    private func presentPortError() {
        let alert = NSAlert()
        alert.messageText = "PharoNativeBrowser was launched without --port=N"
        alert.informativeText = """
        Launch this app via the Pharo Browse menu so it can pass the bridge \
        port. Direct double-click is not supported in v1.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            windowControllers.removeAll { $0.window === window }
        }
    }
}
