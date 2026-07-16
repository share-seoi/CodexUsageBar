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
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
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
