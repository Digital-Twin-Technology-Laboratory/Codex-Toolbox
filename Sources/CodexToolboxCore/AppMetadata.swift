import Foundation

public enum AppMetadata {
    public static let displayName = "Codex Toolbox"
    public static let bundleIdentifier = "io.github.zzzzzzjw.ShowCodexIQ"
    public static let radarURL = URL(string: "https://codexradar.com/")!
    public static let radarJSONURL = URL(string: "https://codexradar.com/current.json")!
    public static let repositoryURL = URL(
        string: "https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox"
    )!

    public static var version: String {
        version(in: Bundle.main.infoDictionary)
    }

    public static var build: String {
        build(in: Bundle.main.infoDictionary)
    }

    static func version(in infoDictionary: [String: Any]?) -> String {
        bundleString("CodexToolboxReleaseVersion", in: infoDictionary)
            ?? bundleString("ShowCodexIQReleaseVersion", in: infoDictionary)
            ?? bundleString("CFBundleShortVersionString", in: infoDictionary)
            ?? "0.0.0-dev"
    }

    static func build(in infoDictionary: [String: Any]?) -> String {
        bundleString("CFBundleVersion", in: infoDictionary) ?? "0"
    }

    private static func bundleString(
        _ key: String,
        in infoDictionary: [String: Any]?
    ) -> String? {
        guard let value = infoDictionary?[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
