import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let port: UInt16
    private var server: WidgetServer?
    private var menu: AppMenuController?

    init(port: UInt16) {
        self.port = port
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu = AppMenuController()
        menu?.install()

        let server = WidgetServer(port: port)
        self.server = server
        do {
            try server.start()
            NSLog("PharoNativeShell: listening on 127.0.0.1:%u", port)
        } catch {
            let alert = NSAlert()
            alert.messageText = "PharoNativeShell failed to start"
            alert.informativeText = "Could not bind 127.0.0.1:\(port): \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The shell exists to render windows on Pharo's behalf. When the
        // last Pharo-owned window goes away we keep running, so Pharo can
        // open new ones on demand. Quit explicitly from the app menu.
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }
}
