import Foundation

/// Resolves where the Nora CLI and its Go helpers live.
///
/// The app is a front end for the CLI; it bundles nothing and runs no cleanup
/// logic of its own. Candidates are ordered so an explicit override wins, then
/// the standard install, then a source checkout — a machine with both should
/// use what was installed.
enum NoraLocator {
    /// Resolved once per launch. `MenuBarPopover` read this in `body`, which
    /// meant four executable stats every 2s while the popover was open — for
    /// an answer that cannot change without restarting the app (the settings
    /// field even says so).
    static let cachedSetupProblem: String? = setupProblem

    static let repoPathDefaultsKey = "noraCLIPath"

    /// Where `install.sh` puts the CLI.
    static let defaultInstallPath = ".nora"

    /// Root of the CLI tree, or nil when none of the candidates exist.
    static var repoRoot: URL? {
        var candidates: [URL] = []
        let home = FileManager.default.homeDirectoryForCurrentUser

        // Set in Settings when the CLI lives somewhere unusual.
        if let custom = UserDefaults.standard.string(forKey: repoPathDefaultsKey), !custom.isEmpty {
            candidates.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath))
        }

        candidates.append(home.appending(path: defaultInstallPath))

        // A source checkout, for working on Nora itself. `app/` sits inside the
        // repo, so the CLI is two levels up from the built binary.
        candidates.append(
            Bundle.main.bundleURL
                .deletingLastPathComponent()   // dist/
                .deletingLastPathComponent()   // app/
                .deletingLastPathComponent()   // repo root
        )

        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.appending(path: "nora").path)
        }
    }

    /// The `nora` bash entrypoint, used for clean/uninstall/optimize.
    static var entrypoint: URL? {
        guard let root = repoRoot else { return nil }
        let url = root.appending(path: "nora")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// The compiled `status` collector. Invoked directly rather than through the
    /// bash entrypoint so the stream starts without the wrapper's startup cost.
    static var statusBinary: URL? { goBinary(named: "status-go") }

    /// The compiled disk analyzer.
    static var analyzeBinary: URL? { goBinary(named: "analyze-go") }

    private static func goBinary(named name: String) -> URL? {
        guard let root = repoRoot else { return nil }
        let url = root.appending(path: "bin/\(name)")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Human-readable reason the app cannot run, or nil when everything resolves.
    static var setupProblem: String? {
        guard let root = repoRoot else {
            return "Không tìm thấy bản cài Nora. Đặt đường dẫn trong Cài đặt."
        }
        if statusBinary == nil {
            return "Thiếu bin/status-go trong \(root.path). Cài lại Nora, hoặc chạy `make build` nếu chạy từ mã nguồn."
        }
        return nil
    }

    /// Path to the cleanup preview that `nora clean --dry-run` writes.
    static var cleanListFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/nora/clean-list.txt")
    }
}
