import AppKit
import Foundation
import ImageIO

enum ProviderIconLoader {
    private static var cache: [String: NSImage] = [:]

    static func currentIcon(for provider: UsageProvider) -> NSImage? {
        switch provider {
        case .codex:
            return codexIcon()
        case .claude:
            return claudeIcon()
        }
    }

    private static func codexIcon() -> NSImage? {
        let darkMode = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fileName = darkMode ? "icon-codex-dark-color" : "icon-codex-light"

        if let cached = cache[fileName] {
            return cached
        }

        var candidates: [URL] = []
        if let bundledURL = Bundle.main.url(forResource: fileName, withExtension: "png") {
            candidates.append(bundledURL)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let resourceRoots = [
            "/Applications/ChatGPT.app/Contents/Resources",
            "/Applications/Codex.app/Contents/Resources",
            "\(home)/Applications/ChatGPT.app/Contents/Resources",
            "\(home)/Applications/Codex.app/Contents/Resources"
        ]
        for root in resourceRoots {
            candidates.append(URL(fileURLWithPath: "\(root)/\(fileName).png"))
        }

        guard let image = loadDownsampledIcon(from: candidates) else {
            return NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex")
        }
        image.isTemplate = false
        cache[fileName] = image
        return image
    }

    // Claude 앱의 메뉴 막대용 템플릿 아이콘을 그대로 사용해 라이트/다크 모드에 자동으로 맞춘다.
    private static func claudeIcon() -> NSImage? {
        let cacheKey = "claude-tray-template"
        if let cached = cache[cacheKey] {
            return cached
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/Claude.app/Contents/Resources",
            "\(home)/Applications/Claude.app/Contents/Resources"
        ].flatMap { root in
            ["TrayIconTemplate@2x.png", "TrayIconTemplate.png"].map {
                URL(fileURLWithPath: "\(root)/\($0)")
            }
        }

        guard let image = loadDownsampledIcon(from: candidates) else {
            return NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude")
        }
        image.isTemplate = true
        cache[cacheKey] = image
        return image
    }

    private static func loadDownsampledIcon(from candidates: [URL]) -> NSImage? {
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
