import AppKit

let app = NSApplication.shared
let delegate = VOCRAppDelegate(arguments: Array(CommandLine.arguments.dropFirst()))

app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
