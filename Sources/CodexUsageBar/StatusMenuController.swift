import AppKit
import SwiftUI

final class StatusMenuController: NSObject, NSMenuDelegate {
    var onRefresh: (() -> Void)?
    var onMenuOpened: (() -> Void)?
    var onShowBothChanged: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    // "둘 다 표시"일 때만 만드는 두 번째 항목. 나중에 만든 항목이 왼쪽에 붙으므로 여기에 Codex를 둔다.
    private var secondaryItem: NSStatusItem?
    private let model: UsageBoardModel
    private let boardView: NSHostingView<UsageBoardView>
    private let showBothItem = NSMenuItem(
        title: "Codex·Claude 둘 다 표시",
        action: #selector(StatusMenuController.toggleShowBoth),
        keyEquivalent: "b"
    )

    init(activeProvider: UsageProvider, showBoth: Bool) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let model = UsageBoardModel(activeProvider: activeProvider)
        model.showBoth = showBoth
        self.model = model
        boardView = NSHostingView(rootView: UsageBoardView(model: model))
        super.init()
        configureStatusItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusButton()
        resizeBoard()
        onMenuOpened?()
    }

    func setActiveProvider(_ provider: UsageProvider) {
        guard provider != model.activeProvider else { return }
        model.activeProvider = provider
        updateStatusButton()
    }

    func render(_ snapshot: UsageSnapshot, for provider: UsageProvider) {
        model.update(provider) { $0.snapshot = snapshot }
        resizeBoard()
        // A snapshot arriving for the other app can turn "둘 다 표시" from one item into two.
        updateStatusButton()
    }

    func markChecked(at date: Date, for provider: UsageProvider) {
        model.update(provider) { $0.checkedAt = date }
    }

    func setConnectionStatus(_ status: String, health: ConnectionHealth, for provider: UsageProvider) {
        model.update(provider) {
            $0.status = status
            $0.health = health
        }
        resizeBoard()
    }

    private func configureStatusItem() {
        configureButton(statusItem.button)
        updateStatusButton()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let boardItem = NSMenuItem()
        boardItem.view = boardView
        resizeBoard()
        menu.addItem(boardItem)
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: "지금 새로고침",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = true
        menu.addItem(refreshItem)

        showBothItem.target = self
        showBothItem.isEnabled = true
        showBothItem.state = model.showBoth ? .on : .off
        menu.addItem(showBothItem)

        let quitItem = NSMenuItem(
            title: "Codex Usage Bar 종료",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func configureButton(_ button: NSStatusBarButton?) {
        guard let button else { return }
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
    }

    // 메뉴 항목 안의 SwiftUI 뷰는 내용이 바뀌어도 크기가 자동으로 맞춰지지 않아 직접 갱신한다.
    private func resizeBoard() {
        let size = boardView.fittingSize
        boardView.setFrameSize(NSSize(width: UsageBoardView.width, height: size.height))
    }

    private func updateStatusButton() {
        let shown = model.shownProviders
        // 오른쪽(원래 항목)에 마지막 앱, 왼쪽(두 번째 항목)에 첫 번째 앱을 그린다.
        show(shown[shown.count - 1], on: statusItem.button)
        if shown.count > 1 {
            let item = secondaryItem ?? makeSecondaryItem()
            show(shown[0], on: item.button)
        } else if let item = secondaryItem {
            NSStatusBar.system.removeStatusItem(item)
            secondaryItem = nil
        }
    }

    private func makeSecondaryItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton(item.button)
        // NSMenu는 한 항목에만 붙일 수 있으므로, 눌리면 원래 항목의 메뉴를 연다.
        item.button?.target = self
        item.button?.action = #selector(openMenu)
        secondaryItem = item
        return item
    }

    private func show(_ provider: UsageProvider, on button: NSStatusBarButton?) {
        guard let button else { return }
        let name = provider.displayName
        if let snapshot = model.state(for: provider).snapshot, !snapshot.windows.isEmpty {
            button.title = snapshot.menuBarTitle
            button.toolTip = "\(name) \(snapshot.menuBarToolTip)"
        } else {
            button.title = "--%"
            button.toolTip = "\(name) 남은 사용량 확인 중"
        }
        if let image = ProviderIconLoader.currentIcon(for: provider) {
            button.image = image
        }
    }

    @objc private func openMenu() {
        statusItem.button?.performClick(nil)
    }

    @objc private func refreshNow() {
        onRefresh?()
    }

    @objc private func toggleShowBoth() {
        model.showBoth.toggle()
        showBothItem.state = model.showBoth ? .on : .off
        updateStatusButton()
        onShowBothChanged?(model.showBoth)
    }

    @objc private func quit() {
        onQuit?()
    }
}
