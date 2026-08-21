import Foundation

public enum DashboardTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case colorfulGlass
    case clearGlass
    case flatNeutral

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .colorfulGlass: "彩色玻璃"
        case .clearGlass: "纯净玻璃"
        case .flatNeutral: "简约平面"
        }
    }
}
