import Foundation
import RepoBarCore

extension AppState {
    func fetchActivityRepos() async throws -> GitHubClient.FetchReposResult {
        let mode = self.session.settings.repoList.fetchMode
        let pinnedNames = self.session.settings.repoList.pinnedRepositories
        return try await self.github.activityRepositories(mode: mode, pinnedRepoNames: pinnedNames)
    }

    func fetchGlobalActivityEvents(
        username: String,
        scope: GlobalActivityScope,
        repos: [Repository]
    ) async -> GlobalActivityResult {
        let repoEvents = repos.flatMap(\.activityEvents)
        async let activityResult: Result<[ActivityEvent], Error> = self.capture {
            try await self.github.userActivityEvents(
                username: username,
                scope: scope,
                limit: AppLimits.GlobalActivity.limit
            )
        }
        async let commitResult: Result<[RepoCommitSummary], Error> = self.capture {
            try await self.github.userCommitEvents(
                username: username,
                scope: scope,
                limit: AppLimits.GlobalCommits.limit
            )
        }

        let activityEvents: [ActivityEvent]
        let activityError: String?
        switch await activityResult {
        case let .success(events):
            activityEvents = events
            activityError = nil
        case let .failure(error):
            activityEvents = []
            activityError = error.userFacingMessage
        }

        let commitEvents: [RepoCommitSummary]
        let commitError: String?
        switch await commitResult {
        case let .success(commits):
            commitEvents = commits
            commitError = nil
        case let .failure(error):
            commitEvents = []
            commitError = error.userFacingMessage
        }

        let merged = self.mergeGlobalActivityEvents(
            userEvents: activityEvents,
            repoEvents: repoEvents,
            scope: scope,
            username: username,
            limit: AppLimits.GlobalActivity.limit
        )

        return GlobalActivityResult(
            events: merged,
            commits: commitEvents,
            error: activityError,
            commitError: commitError
        )
    }

    private func mergeGlobalActivityEvents(
        userEvents: [ActivityEvent],
        repoEvents: [ActivityEvent],
        scope: GlobalActivityScope,
        username: String,
        limit: Int
    ) -> [ActivityEvent] {
        let combined = userEvents + repoEvents
        let filtered = scope == .myActivity
            ? combined.filter { $0.actor.caseInsensitiveCompare(username) == .orderedSame }
            : combined
        let sorted = filtered.sorted { $0.date > $1.date }
        var seen: Set<String> = []
        var results: [ActivityEvent] = []
        results.reserveCapacity(limit)
        for event in sorted {
            let key = "\(event.url.absoluteString)|\(event.date.timeIntervalSinceReferenceDate)|\(event.actor)"
            guard seen.insert(key).inserted else { continue }
            results.append(event)
            if results.count >= limit { break }
        }
        return results
    }

    private func capture<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return try await .success(work()) } catch { return .failure(error) }
    }
}
