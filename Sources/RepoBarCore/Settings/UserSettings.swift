import Foundation

public struct UserSettings: Equatable, Codable {
    public var appearance = AppearanceSettings()
    public var heatmap = HeatmapSettings()
    public var repoList = RepoListSettings()
    public var localProjects = LocalProjectsSettings()
    public var menuCustomization = MenuCustomization()
    public var refreshInterval: RefreshInterval = .fiveMinutes
    public var launchAtLogin = false
    public var debugPaneEnabled: Bool = false
    public var diagnosticsEnabled: Bool = false
    public var loggingVerbosity: LogVerbosity = .info
    public var fileLoggingEnabled: Bool = false
    public var githubHost: URL = .init(string: "https://github.com")!
    public var enterpriseHost: URL?
    public var loopbackPort: Int = 53682
    public var pkceMode: PKCEMode = .auto

    public init() {}
}

public enum PKCEMode: String, CaseIterable, Equatable, Codable {
    case auto
    case on
    case off

    public var label: String {
        switch self {
        case .auto: "Auto (recommended)"
        case .on: "Always on"
        case .off: "Off (legacy GHE < 3.15)"
        }
    }

    public var description: String {
        switch self {
        case .auto: "Enables PKCE for GitHub.com and GHE 3.15+, disables for older GHE"
        case .on: "Always use PKCE (may fail on older GitHub Enterprise)"
        case .off: "Disable PKCE (less secure, for GHE < 3.15 compatibility)"
        }
    }
}

public struct HeatmapSettings: Equatable, Codable {
    public var display: HeatmapDisplay = .inline
    public var span: HeatmapSpan = .twelveMonths

    public init() {}
}

public struct RepoListSettings: Equatable, Codable {
    public var displayLimit: Int = 6
    public var showForks = false
    public var showArchived = false
    public var menuSortKey: RepositorySortKey = .activity
    public var pinnedRepositories: [String] = [] // owner/name
    public var hiddenRepositories: [String] = [] // owner/name
    public var ownerFilter: [String] = [] // owner names to include (empty = show all)
    public var fetchMode: RepoFetchMode = .standard
    public var enterpriseModePromptShown: Bool = false

    public init() {}
}

public enum RepoFetchMode: String, CaseIterable, Equatable, Codable, Sendable {
    case standard       // Fetch up to ~100 repos (first page), suitable for most users
    case pinnedOnly     // Only fetch pinned repos (fastest, for enterprise)
    case unlimited      // Fetch all accessible repos (original behavior, can be slow)

    public var label: String {
        switch self {
        case .standard: "Standard (up to 100 repos)"
        case .pinnedOnly: "Pinned only (fastest)"
        case .unlimited: "All accessible repos (slow for enterprise)"
        }
    }

    public var description: String {
        switch self {
        case .standard: "Fetches up to 100 most recently active repos. Good balance of speed and coverage."
        case .pinnedOnly: "Only fetches repos you've pinned. Fastest option for enterprise accounts with many repos."
        case .unlimited: "Fetches all repos you have access to. Can be very slow for enterprise accounts."
        }
    }

    public var fetchLimit: Int? {
        switch self {
        case .standard: 100
        case .pinnedOnly: nil // Special handling - only fetch pinned
        case .unlimited: nil
        }
    }
}

public struct AppearanceSettings: Equatable, Codable {
    public var showContributionHeader = true
    public var cardDensity: CardDensity = .comfortable
    public var accentTone: AccentTone = .githubGreen
    public var activityScope: GlobalActivityScope = .myActivity

    public init() {}
}

public struct LocalProjectsSettings: Equatable, Codable {
    public var rootPath: String?
    public var rootBookmarkData: Data?
    public var autoSyncEnabled: Bool = true
    public var showDirtyFilesInMenu: Bool = false
    public var fetchInterval: LocalProjectsRefreshInterval = .fiveMinutes
    public var worktreeFolderName: String = ".work"
    public var preferredTerminal: String?
    public var ghosttyOpenMode: GhosttyOpenMode = .tab
    public var preferredLocalPathsByFullName: [String: String] = [:]

    public init() {
        #if DEBUG
            self.rootPath = "~/Projects"
        #endif
    }
}

public enum LocalProjectsRefreshInterval: String, CaseIterable, Equatable, Codable {
    case oneMinute
    case twoMinutes
    case fiveMinutes
    case fifteenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }

    public var label: String {
        switch self {
        case .oneMinute: "1 minute"
        case .twoMinutes: "2 minutes"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        }
    }
}

public enum GhosttyOpenMode: String, CaseIterable, Equatable, Codable {
    case newWindow
    case tab

    public var label: String {
        switch self {
        case .newWindow: "New Window"
        case .tab: "Tab"
        }
    }
}

public enum RefreshInterval: CaseIterable, Equatable, Codable {
    case oneMinute, twoMinutes, fiveMinutes, fifteenMinutes

    public var seconds: TimeInterval {
        switch self {
        case .oneMinute: 60
        case .twoMinutes: 120
        case .fiveMinutes: 300
        case .fifteenMinutes: 900
        }
    }
}

public enum HeatmapDisplay: String, CaseIterable, Equatable, Codable {
    case inline
    case submenu

    public var label: String {
        switch self {
        case .inline: "Inline"
        case .submenu: "Submenu"
        }
    }
}

public enum CardDensity: String, CaseIterable, Equatable, Codable {
    case comfortable
    case compact

    public var label: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }
}

public enum AccentTone: String, CaseIterable, Equatable, Codable {
    case system
    case githubGreen

    public var label: String {
        switch self {
        case .system: "System accent"
        case .githubGreen: "GitHub greens"
        }
    }
}

public enum GlobalActivityScope: String, CaseIterable, Equatable, Codable, Sendable {
    case allActivity
    case myActivity

    public var label: String {
        switch self {
        case .allActivity: "All activity"
        case .myActivity: "My activity"
        }
    }
}
