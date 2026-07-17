import Foundation

public enum ToolboxModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case modelRadar
    case tokenUsage
    case resetCredits

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .modelRadar: "模型智商"
        case .tokenUsage: "Token 用量"
        case .resetCredits: "重置卡"
        }
    }

    public var systemImage: String {
        switch self {
        case .modelRadar: "brain.head.profile"
        case .tokenUsage: "chart.bar.xaxis"
        case .resetCredits: "arrow.clockwise.circle"
        }
    }
}

public struct DashboardConfiguration: Codable, Hashable, Sendable {
    public let orderedModules: [ToolboxModule]
    public let hiddenModules: Set<ToolboxModule>
    public let collapsedModules: Set<ToolboxModule>

    public static let `default` = DashboardConfiguration(
        orderedModules: ToolboxModule.allCases,
        hiddenModules: [],
        collapsedModules: []
    )

    public init(
        orderedModules: [ToolboxModule],
        hiddenModules: Set<ToolboxModule>,
        collapsedModules: Set<ToolboxModule>
    ) {
        var seen = Set<ToolboxModule>()
        let unique = orderedModules.filter { seen.insert($0).inserted }
        self.orderedModules = unique + ToolboxModule.allCases.filter { !seen.contains($0) }
        self.hiddenModules = hiddenModules.intersection(ToolboxModule.allCases)
        self.collapsedModules = collapsedModules.intersection(ToolboxModule.allCases)
    }

    public var visibleModules: [ToolboxModule] {
        orderedModules.filter { !hiddenModules.contains($0) }
    }
}
