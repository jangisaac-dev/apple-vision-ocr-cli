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
        message: "준비됨"
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
            button.title = "VOCR 완료"
        case .failed:
            button.title = "VOCR 실패"
        case .canceled:
            button.title = "VOCR 취소"
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
            title: "상세 창 보기",
            action: #selector(showWindow),
            keyEquivalent: ""
        ).targeting(self))

        switch snapshot.state {
        case .running:
            menu.addItem(NSMenuItem(
                title: "일시정지",
                action: #selector(pause),
                keyEquivalent: ""
            ).targeting(self))
            menu.addItem(NSMenuItem(
                title: "취소",
                action: #selector(cancel),
                keyEquivalent: ""
            ).targeting(self))
        case .paused:
            menu.addItem(NSMenuItem(
                title: "이어서 진행",
                action: #selector(resume),
                keyEquivalent: ""
            ).targeting(self))
            menu.addItem(NSMenuItem(
                title: "취소",
                action: #selector(cancel),
                keyEquivalent: ""
            ).targeting(self))
        default:
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(
                title: "종료",
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
            return "준비됨"
        case .completed:
            return "완료됨"
        case .failed:
            return "실패"
        case .canceled:
            return "취소됨"
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
