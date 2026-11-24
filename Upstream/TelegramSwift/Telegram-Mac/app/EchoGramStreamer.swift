import AppKit
import Carbon.HIToolbox
import UserNotifications

final class EchoGramStreamer: NSObject {
    static let shared = EchoGramStreamer()
    private static let preferenceKey = "EchoGramStreamerMode"
    private static let windowShortcutKeys: Set<UInt16> = [
        UInt16(kVK_ANSI_H), UInt16(kVK_ANSI_M), UInt16(kVK_ANSI_Q), UInt16(kVK_ANSI_W)
    ]

    static var isActive: Bool { UserDefaults.standard.bool(forKey: preferenceKey) }

    private final class CoveredWindow {
        weak var window: NSWindow?

        init(_ window: NSWindow) {
            self.window = window
        }
    }

    private final class CoveredView {
        weak var view: NSView?
        let wasHidden: Bool

        init(_ view: NSView) {
            self.view = view
            self.wasHidden = view.isHidden
        }
    }

    private var updatingWindowMask = false
    private var mask: NSView?
    private var keyMonitor: Any?
    private var coveredViews: [ObjectIdentifier: CoveredView] = [:]
    private weak var primaryWindow: NSWindow?
    private var originalTitle: String?
    private var originalSubtitle: String?
    private var coveredWindows: [ObjectIdentifier: CoveredWindow] = [:]
    private var update: ((Bool) -> Void)?
    private weak var menuItem: NSMenuItem?

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowUpdated), name: NSWindow.didBecomeKeyNotification, object: nil)
        center.addObserver(self, selector: #selector(windowUpdated), name: NSWindow.didUpdateNotification, object: nil)
    }

    func attach(window: NSWindow, update: @escaping (Bool) -> Void) {
        primaryWindow = window
        self.update = update
        installMenu()
        apply(Self.isActive)
    }

    @objc private func windowUpdated() {
        installMenu()
        if Self.isActive { coverWindows() }
    }

    @objc private func toggle() {
        let active = !Self.isActive
        UserDefaults.standard.set(active, forKey: Self.preferenceKey)
        apply(active)
    }

    private func installMenu() {
        guard menuItem == nil, let rootMenu = NSApp.mainMenu else { return }
        let menu = NSMenu(title: "EchoGram")
        let item = NSMenuItem(title: "Режим стримера", action: #selector(toggle), keyEquivalent: "s") //TODOLANG
        item.target = self
        item.keyEquivalentModifierMask = [.command, .shift]
        item.state = Self.isActive ? .on : .off
        menu.addItem(item)
        menuItem = item
        let group = NSMenuItem(title: "EchoGram", action: nil, keyEquivalent: "")
        group.submenu = menu
        rootMenu.insertItem(group, at: max(0, rootMenu.items.count - 1))
    }

    private func apply(_ active: Bool) {
        menuItem?.state = active ? .on : .off
        update?(active)
        if active {
            if originalTitle == nil {
                originalTitle = primaryWindow?.title
                originalSubtitle = primaryWindow?.subtitle
            }
            primaryWindow?.title = "EchoGram"
            primaryWindow?.subtitle = ""
            primaryWindow?.makeFirstResponder(nil)
            if keyMonitor == nil {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let window = self?.primaryWindow, event.window === window else { return event }
                    let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
                    if modifiers == [.command, .shift], event.keyCode == UInt16(kVK_ANSI_S) { return event }
                    if modifiers == [.command], Self.windowShortcutKeys.contains(event.keyCode) { return event }
                    return nil
                }
            }
            coverWindows()
            let notifications = UNUserNotificationCenter.current()
            notifications.removeAllPendingNotificationRequests()
            notifications.removeAllDeliveredNotifications()
        } else {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
            uncoverMainContent()
            if let originalTitle { primaryWindow?.title = originalTitle }
            if let originalSubtitle { primaryWindow?.subtitle = originalSubtitle }
            originalTitle = nil
            originalSubtitle = nil
            let windows = coveredWindows.values.compactMap(\.window)
            coveredWindows.removeAll()
            for window in windows where NSApp.windows.contains(window) {
                window.orderFront(nil)
            }
        }
    }

    private func coverWindows() {
        guard !updatingWindowMask, let primaryWindow else { return }
        updatingWindowMask = true
        defer { updatingWindowMask = false }
        if let content = primaryWindow.contentView {
            coverMainContent(content)
        }
        for window in NSApp.windows where window !== primaryWindow && window.isVisible {
            let key = ObjectIdentifier(window)
            if coveredWindows[key] == nil { coveredWindows[key] = CoveredWindow(window) }
            window.orderOut(nil)
        }
        if primaryWindow.title != "EchoGram" { primaryWindow.title = "EchoGram" }
        if !primaryWindow.subtitle.isEmpty { primaryWindow.subtitle = "" }
    }

    private func coverMainContent(_ content: NSView) {
        if mask?.superview !== content {
            uncoverMainContent()
            let replacement = Self.makePrivacyView(frame: content.bounds)
            content.addSubview(replacement, positioned: .above, relativeTo: nil)
            mask = replacement
        }
        for view in content.subviews where view !== mask {
            let key = ObjectIdentifier(view)
            if coveredViews[key]?.view == nil { coveredViews[key] = CoveredView(view) }
            if !view.isHidden { view.isHidden = true }
        }
    }

    private func uncoverMainContent() {
        mask?.removeFromSuperview()
        mask = nil
        for covered in coveredViews.values {
            covered.view?.isHidden = covered.wasHidden
        }
        coveredViews.removeAll()
    }

    private static func makePrivacyView(frame: NSRect) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.zPosition = 1_000
        view.autoresizingMask = [.width, .height]

        let title = NSTextField(labelWithString: "Режим стримера") //TODOLANG
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let shortcut = NSTextField(labelWithString: "⇧⌘S")
        shortcut.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, shortcut])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }
}
