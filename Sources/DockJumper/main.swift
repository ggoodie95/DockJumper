import AppKit
import Foundation
import QuartzCore
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
        applyApplicationIcon()

        let windowSize = NSSize(width: 520, height: 360)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        var targetFrame = NSRect(origin: .zero, size: windowSize)
        if let visible = NSScreen.main?.visibleFrame {
            let baseline = visible.minY + 16
            let origin = CGPoint(
                x: visible.midX - windowSize.width / 2,
                y: baseline
            )
            targetFrame = NSRect(origin: origin, size: windowSize)
            let startOrigin = CGPoint(x: origin.x, y: visible.minY - windowSize.height - 40)
            window.setFrame(NSRect(origin: startOrigin, size: windowSize), display: false)
        } else {
            window.center()
            targetFrame = window.frame
        }
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
        if NSScreen.main != nil {
            let finalFrame = targetFrame
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(finalFrame, display: true)
            }
        }
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(self)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        return true
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

    private func applyApplicationIcon() {
        guard let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
            let icon = NSImage(contentsOf: iconURL)
        else {
            return
        }
        NSApplication.shared.applicationIconImage = icon

        if let executableURL = Bundle.main.executableURL {
            _ = NSWorkspace.shared.setIcon(
                icon,
                forFile: executableURL.path,
                options: []
            )
        }
    }
}
