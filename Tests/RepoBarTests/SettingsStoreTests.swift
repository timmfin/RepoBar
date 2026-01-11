import Foundation
@testable import RepoBarCore
import Testing

struct SettingsStoreTests {
    @Test
    func saveAndLoad() throws {
        let suiteName = "repobar.settings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == UserSettings())

        var settings = UserSettings()
        settings.repoList.displayLimit = 9
        settings.repoList.pinnedRepositories = ["steipete/RepoBar", "steipete/clawdis"]
        settings.repoList.hiddenRepositories = ["steipete/agent-scripts"]
        settings.enterpriseHost = URL(string: "https://ghe.example.com")!
        settings.debugPaneEnabled = true

        store.save(settings)
        #expect(store.load() == settings)
    }

    @Test
    func saveAndLoad_persistsLocalProjectsBookmark() throws {
        let suiteName = "repobar.settings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        var settings = UserSettings()
        settings.localProjects.rootPath = "~/Projects"
        settings.localProjects.rootBookmarkData = Data([0x01, 0x02, 0x03, 0x04])

        store.save(settings)
        let loaded = store.load()
        #expect(loaded.localProjects.rootPath == "~/Projects")
        #expect(loaded.localProjects.rootBookmarkData == Data([0x01, 0x02, 0x03, 0x04]))
    }

    @Test
    func saveAndLoad_persistsPKCEMode() throws {
        let suiteName = "repobar.settings.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        var settings = UserSettings()
        #expect(settings.pkceMode == .auto)

        settings.pkceMode = .off
        store.save(settings)
        #expect(store.load().pkceMode == .off)

        settings.pkceMode = .on
        store.save(settings)
        #expect(store.load().pkceMode == .on)
    }
}
