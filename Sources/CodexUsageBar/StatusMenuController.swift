import AppKit
import SwiftUI

final class StatusMenuController: NSObject, NSMenuDelegate {
    var onRefresh: (() -> Void)?
    var onMenuOpened: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let model: UsageBoardModel
    private let boardView: NSHostingView<UsageBoardView>

    init(activeProvider: UsageProvider) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        model = UsageBoardModel(activeProvider: activeProvider)
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
        if provider == model.activeProvider {
            updateStatusButton()
        }
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
        if let button = statusItem.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
        }
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

    // 메뉴 항목 안의 SwiftUI 뷰는 내용이 바뀌어도 크기가 자동으로 맞춰지지 않아 직접 갱신한다.
    private func resizeBoard() {
        let size = boardView.fittingSize
        boardView.setFrameSize(NSSize(width: UsageBoardView.width, height: size.height))
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        let provider = model.activeProvider
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

    @objc private func refreshNow() {
        onRefresh?()
    }

    @objc private func quit() {
        onQuit?()
    }
}
