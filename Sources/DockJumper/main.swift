import AppKit
import SpriteKit

@main
struct DockJumperApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        let windowSize = NSSize(width: 480, height: 320)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "DockJumper"
        window.level = .floating
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: windowSize))
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let skView = SKView(frame: contentView.bounds)
        skView.autoresizingMask = [.width, .height]
        skView.preferredFramesPerSecond = 60
        skView.ignoresSiblingOrder = true
        contentView.addSubview(skView)

        let scene = GameScene(size: CGSize(width: windowSize.width, height: windowSize.height))
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let quitTitle = "Quit DockJumper"
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}
