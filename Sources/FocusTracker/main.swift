import AppKit

// Menubar-only app: `.accessory` means no Dock icon and no app menu,
// just the status item. (The packaged .app also sets LSUIElement.)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
