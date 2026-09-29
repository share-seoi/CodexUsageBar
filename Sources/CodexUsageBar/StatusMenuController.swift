import AppKit
import SwiftUI

final class StatusMenuController: NSObject, NSMenuDelegate {
    var onRefresh: (() -> Void)?
    var onMenuOpened: (() -> Void)?
    var onShowBothChanged: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    // "둘 다 표시"도 두 번째 항목을 만들지 않고 이 항목 하나에 나란히 그린다.
    // 새 항목은 맨 왼쪽에 붙어서 메뉴 막대가 꽉 차면 노치 뒤로 숨어 버린다.
    private let statusItem: NSStatusItem
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
        guard let button = statusItem.button else { return }
        let shown = model.shownProviders
        guard shown.count > 1 else {
            show(shown[0], on: button)
            return
        }

        // 아이콘을 글자 사이에 넣어 "[Codex] W 88%   [Claude] 5h 63% · W 88%"처럼 그린다.
        let font = button.font ?? .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let title = NSMutableAttributedString()
        for (index, provider) in shown.enumerated() {
            if index > 0 {
                title.append(NSAttributedString(string: "   ", attributes: [.font: font]))
            }
            if let icon = ProviderIconLoader.currentIcon(for: provider) {
                title.append(Self.inlineIcon(icon, font: font))
                title.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }
            title.append(NSAttributedString(string: menuBarTitle(for: provider), attributes: [.font: font]))
        }
        button.image = nil
        button.attributedTitle = title
        button.toolTip = shown.map(toolTip(for:)).joined(separator: "\n")
    }

    private func show(_ provider: UsageProvider, on button: NSStatusBarButton) {
        button.title = menuBarTitle(for: provider)
        button.toolTip = toolTip(for: provider)
        if let image = ProviderIconLoader.currentIcon(for: provider) {
            button.image = image
        }
    }

    private func menuBarTitle(for provider: UsageProvider) -> String {
        guard let snapshot = model.state(for: provider).snapshot, !snapshot.windows.isEmpty else {
            return "--%"
        }
        return snapshot.menuBarTitle
    }

    private func toolTip(for provider: UsageProvider) -> String {
        let name = provider.displayName
        guard let snapshot = model.state(for: provider).snapshot, !snapshot.windows.isEmpty else {
            return "\(name) 남은 사용량 확인 중"
        }
        return "\(name) \(snapshot.menuBarToolTip)"
    }

    /// 글자 사이에 넣은 이미지는 템플릿이어도 자동으로 칠해지지 않으므로, 그릴 때 메뉴 막대 글자색을 입힌다.
    private static func inlineIcon(_ icon: NSImage, font: NSFont) -> NSAttributedString {
        let side: CGFloat = 16
        let size = NSSize(width: side, height: side)
        let image: NSImage
        if icon.isTemplate {
            image = NSImage(size: size, flipped: false) { rect in
                icon.draw(in: rect)
                NSColor.labelColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        } else {
            image = icon
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - side) / 2, width: side, height: side)
        return NSAttributedString(attachment: attachment)
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
