import AppKit

final class StatusItemController: NSObject {
    var onShowWindow: () -> Void = {}
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}
    var onCancel: () -> Void = {}

    private let statusItem: NSStatusItem
    private var snapshot = VOCRProgressSnapshot(
        state: .idle,
        currentFile: nil,
        completedFiles: 0,
        totalFiles: 0,
        completedPages: 0,
        totalPages: 0,
        percent: 0,
        message: VOCRStrings.statusReady.text
    )

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        update(snapshot)
    }

    func update(_ snapshot: VOCRProgressSnapshot) {
        self.snapshot = snapshot
        guard let button = statusItem.button else {
            return
        }

        switch snapshot.state {
        case .running, .paused:
            button.title = "VOCR \(snapshot.percent)%"
        case .completed:
            button.title = VOCRStrings.statusItemCompleted.text
        case .failed:
            button.title = VOCRStrings.statusItemFailed.text
        case .canceled:
            button.title = VOCRStrings.statusItemCanceled.text
        case .idle:
            button.title = "VOCR"
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }
        button.title = "VOCR"
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusItem.menu = makeMenu()
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in
                self?.statusItem.menu = nil
            }
        } else {
            onShowWindow()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let status = NSMenuItem(title: menuStatusTitle(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: VOCRStrings.menuShowDetails.text,
            action: #selector(showWindow),
            keyEquivalent: ""
        ).targeting(self))

        switch snapshot.state {
        case .running:
            menu.addItem(NSMenuItem(
                title: VOCRStrings.buttonPause.text,
                action: #selector(pause),
                keyEquivalent: ""
            ).targeting(self))
            menu.addItem(NSMenuItem(
                title: VOCRStrings.buttonCancel.text,
                action: #selector(cancel),
                keyEquivalent: ""
            ).targeting(self))
        case .paused:
            menu.addItem(NSMenuItem(
                title: VOCRStrings.buttonResume.text,
                action: #selector(resume),
                keyEquivalent: ""
            ).targeting(self))
            menu.addItem(NSMenuItem(
                title: VOCRStrings.buttonCancel.text,
                action: #selector(cancel),
                keyEquivalent: ""
            ).targeting(self))
        default:
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(
                title: VOCRStrings.buttonQuit.text,
                action: #selector(quit),
                keyEquivalent: "q"
            ).targeting(self))
        }

        return menu
    }

    private func menuStatusTitle() -> String {
        switch snapshot.state {
        case .running, .paused:
            return "\(snapshot.message) · \(snapshot.percent)%"
        case .idle:
            return VOCRStrings.statusReady.text
        case .completed:
            return VOCRStrings.statusCompleted.text
        case .failed:
            return VOCRStrings.statusFailed.text
        case .canceled:
            return VOCRStrings.statusCanceled.text
        }
    }

    @objc private func showWindow() {
        onShowWindow()
    }

    @objc private func pause() {
        onPause()
    }

    @objc private func resume() {
        onResume()
    }

    @objc private func cancel() {
        onCancel()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSMenuItem {
    func targeting(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
