import AppKit

let args = CommandLine.arguments
var portArg: UInt16 = 0
for arg in args {
    if arg.hasPrefix("--port=") {
        let value = String(arg.dropFirst("--port=".count))
        if let parsed = UInt16(value) {
            portArg = parsed
        }
    }
}

let delegate = AppDelegate(port: portArg)
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
