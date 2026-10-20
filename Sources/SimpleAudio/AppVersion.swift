import Foundation

/// Version and build reported by SimpleAudio (status bar, About sheet, HTTP API, `--version`).
/// Both are stamped into the bundle's `Info.plist` by `Scripts/bundle.sh`.
struct AppVersion: Equatable, CustomStringConvertible, Sendable {
    static let defaultVersion = "0.9.0"

    /// `CFBundleShortVersionString`, e.g. `"0.9.0"`.
    let version: String
    /// `CFBundleVersion` (commit count at bundle time); nil outside a `.app` bundle.
    let build: String?

    init(version: String = Self.defaultVersion, build: String? = nil) {
        self.version = version
        self.build = build
    }

    init(infoDictionary info: [String: Any]?) {
        func value(_ key: String) -> String? {
            guard let s = (info?[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !s.isEmpty,
                  !s.hasPrefix("@") else { return nil }
            return s
        }
        self.init(
            version: value("CFBundleShortVersionString") ?? Self.defaultVersion,
            build: value("CFBundleVersion")
        )
    }

    static let current = AppVersion(infoDictionary: Bundle.main.infoDictionary)

    /// `"0.9.0 (2)"`, or `"0.9.0"` outside a bundle.
    var description: String {
        build.map { "\(version) (\($0))" } ?? version
    }

    /// Status bar & About badge: `"v0.9.0 (2)"` or `"v0.9.0"`.
    var shortLabel: String {
        version.hasPrefix("v") ? description : "v\(description)"
    }

    /// `--version`: `"SimpleAudio 0.9.0 (2)"`.
    var cliLine: String {
        "SimpleAudio \(description)"
    }

    /// `SimpleAudio --version`: print and exit before any audio or UI setup.
    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard arguments.dropFirst().contains("--version") || arguments.dropFirst().contains("-v") else { return }
        print(current.cliLine)
        exit(0)
    }
}
