import Foundation

enum CodexLocator {
    static func executablePath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        var candidates: [String] = []

        if let override = environment["CODEX_CLI_PATH"], !override.isEmpty {
            candidates.append(override)
        }

        let home = fileManager.homeDirectoryForCurrentUser.path
        // 새 앱은 Resources/codex-cli/bin/codex에, 예전 앱은 Resources/codex에 CLI를 둔다.
        let appResources = [
            "/Applications/ChatGPT.app/Contents/Resources",
            "/Applications/Codex.app/Contents/Resources",
            "\(home)/Applications/ChatGPT.app/Contents/Resources",
            "\(home)/Applications/Codex.app/Contents/Resources"
        ]
        candidates.append(contentsOf: appResources.map { "\($0)/codex-cli/bin/codex" })
        candidates.append(contentsOf: appResources.map { "\($0)/codex" })
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                "\($0)/codex"
            })
        }

        return candidates.first(where: fileManager.isExecutableFile(atPath:))
    }
}
