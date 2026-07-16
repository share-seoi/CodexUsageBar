import AppKit
import Foundation
import ImageIO

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let monitor = UsageMonitor(pollInterval: 20)
    private let liveFetcher = LiveUsageFetcher()
    private let lifecycle = CodexLifecycle()
    private let cacheKey = "lastUsageSnapshot"

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var summaryItem: NSMenuItem!
    private var planItem: NSMenuItem!
    private var windowItems: [NSMenuItem] = []
    private var updatedItem: NSMenuItem!
    private var connectionItem: NSMenuItem!
    private var lastSnapshot: UsageSnapshot?
    private var lastCheckedAt: Date?
    private var lastLiveCheckedAt: Date?
    private var liveRefreshInProgress = false
    private var interfaceStarted = false
    private var startupTimeout: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        lifecycle.onCodexLaunched = { [weak self] in
            DispatchQueue.main.async {
                self?.startInterfaceIfNeeded()
            }
        }
        lifecycle.onCodexTerminated = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard let self, !self.lifecycle.isCodexRunning else { return }
                NSApp.terminate(nil)
            }
        }
        lifecycle.startObserving()

        if lifecycle.isCodexRunning {
            startInterfaceIfNeeded()
        } else {
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, !self.lifecycle.isCodexRunning else {
                    self?.startInterfaceIfNeeded()
                    return
                }
                NSApp.terminate(nil)
            }
            startupTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        }
    }

    private func startInterfaceIfNeeded() {
        guard !interfaceStarted else { return }
        interfaceStarted = true
        startupTimeout?.cancel()
        startupTimeout = nil
        configureStatusItem()
        restoreCachedSnapshot()

        monitor.onSnapshot = { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.applyLocal(snapshot)
            }
        }
        monitor.onChecked = { [weak self] checkedAt in
            DispatchQueue.main.async {
                self?.markChecked(at: checkedAt)
            }
        }
        monitor.onStatus = { [weak self] status in
            DispatchQueue.main.async {
                guard let self, !self.liveRefreshInProgress else { return }
                self.connectionItem.title = status
            }
        }
        monitor.start()
        refreshLive(isManual: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTimeout?.cancel()
        lifecycle.stopObserving()
        if interfaceStarted {
            monitor.stop()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatusIcon()
        if
            let lastCheckedAt,
            Date().timeIntervalSince(lastCheckedAt) > 25
        {
            monitor.requestRefresh()
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "--%"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Codex 남은 사용량 확인 중"
        }
        updateStatusIcon()

        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        summaryItem = disabledItem("Codex 남은 사용량 확인 중…")
        menu.addItem(summaryItem)

        planItem = disabledItem("Codex")
        menu.addItem(planItem)
        menu.addItem(.separator())

        for _ in 0..<3 {
            let item = disabledItem("")
            item.isHidden = true
            windowItems.append(item)
            menu.addItem(item)
        }

        updatedItem = disabledItem("확인 대기 중")
        menu.addItem(updatedItem)

        connectionItem = disabledItem("Codex 연결 중…")
        menu.addItem(connectionItem)
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

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func applyLocal(_ snapshot: UsageSnapshot) {
        if let lastLiveCheckedAt, snapshot.fetchedAt <= lastLiveCheckedAt {
            return
        }
        apply(snapshot)
    }

    private func applyLive(_ snapshot: UsageSnapshot) {
        lastLiveCheckedAt = snapshot.fetchedAt
        apply(snapshot)
    }

    private func apply(_ snapshot: UsageSnapshot) {
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        save(snapshot)

        let remaining = snapshot.overallRemainingPercent
        statusItem.button?.title = "\(remaining)%"
        statusItem.button?.toolTip = "Codex \(remaining)% 남음"
        summaryItem.title = "Codex 남은 사용량 \(remaining)%"
        planItem.title = planTitle(snapshot.planType)

        for (index, item) in windowItems.enumerated() {
            guard index < snapshot.windows.count else {
                item.isHidden = true
                continue
            }

            let window = snapshot.windows[index]
            item.title = detailTitle(for: window)
            item.isHidden = false
        }
        updateStatusIcon()
    }

    private func markChecked(at date: Date) {
        lastCheckedAt = date
        updatedItem?.title = "확인: \(Self.updateFormatter.string(from: date))"
    }

    private func planTitle(_ planType: String?) -> String {
        guard let planType else { return "Codex" }
        return "Codex · \(planType.capitalized)"
    }

    private func detailTitle(for window: UsageWindow) -> String {
        var title = "\(window.label): \(window.remainingPercent)% 남음"
        if let resetsAt = window.resetsAt {
            title += " · \(Self.resetFormatter.string(from: resetsAt)) 초기화"
        }
        return title
    }

    private func updateStatusIcon() {
        guard let image = CodexIconLoader.currentIcon() else { return }
        statusItem?.button?.image = image
    }

    private func restoreCachedSnapshot() {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else {
            return
        }
        applyLocal(snapshot.adjustedForCurrentTime())
        connectionItem.title = "저장된 값 · Codex 연결 중…"
    }

    private func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }

    @objc private func refreshNow() {
        refreshLive(isManual: true)
    }

    private func refreshLive(isManual: Bool) {
        guard !liveRefreshInProgress else { return }
        liveRefreshInProgress = true
        connectionItem.title = isManual ? "실시간 계정 새로고침 중…" : "실시간 계정 확인 중…"

        let started = liveFetcher.fetch { [weak self] result in
            guard let self else { return }
            self.liveRefreshInProgress = false

            switch result {
            case .success(let snapshot):
                self.applyLive(snapshot)
                self.markChecked(at: snapshot.fetchedAt)
                self.connectionItem.title = "실시간 계정 확인 완료 · 로컬 20초 추적"
            case .failure(let error):
                self.connectionItem.title = "\(error.localizedDescription) · 로컬 추적 유지"
            }
        }

        if !started {
            liveRefreshInProgress = false
            connectionItem.title = "실시간 계정 조회가 이미 진행 중"
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private static let updateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm:ss"
        return formatter
    }()

    private static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 a h:mm"
        return formatter
    }()
}

enum CodexIconLoader {
    private static var lightIcon: NSImage?
    private static var darkIcon: NSImage?

    static func currentIcon() -> NSImage? {
        let darkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fileName = darkMode ? "icon-codex-dark-color" : "icon-codex-light"

        if darkMode, let darkIcon {
            return darkIcon
        }
        if !darkMode, let lightIcon {
            return lightIcon
        }

        guard let image = loadDownsampledIcon(named: fileName) else {
            return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex")
        }
        image.isTemplate = false

        if darkMode {
            darkIcon = image
        } else {
            lightIcon = image
        }
        return image
    }

    private static func loadDownsampledIcon(named fileName: String) -> NSImage? {
        var candidates: [URL] = []

        if let bundledURL = Bundle.main.url(forResource: fileName, withExtension: "png") {
            candidates.append(bundledURL)
        }

        let resourceRoots = [
            "/Applications/ChatGPT.app/Contents/Resources",
            "/Applications/Codex.app/Contents/Resources",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/ChatGPT.app/Contents/Resources",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/Codex.app/Contents/Resources"
        ]

        for root in resourceRoots {
            candidates.append(URL(fileURLWithPath: "\(root)/\(fileName).png"))
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 36,
            kCGImageSourceShouldCacheImmediately: true
        ]

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            guard
                let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else {
                continue
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: 18, height: 18))
        }

        return nil
    }
}
