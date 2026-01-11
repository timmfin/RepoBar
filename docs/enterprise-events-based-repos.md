# Events-Based Repository Discovery for Enterprise

## Problem

Enterprise GitHub accounts have access to thousands of repositories through organization membership. RepoBar currently fetches ALL accessible repos via `/user/repos`, which:
- Takes minutes to complete
- Causes rate limiting (5000 req/hour)
- Shows repos you've never touched

## Proposed Solution: Events-Based Discovery

Use the GitHub Events API to discover repos you've actually worked on recently.

### How It Works

1. **Fetch user events**: `GET /users/{username}/events` (paginated, up to 300 events / ~90 days)
2. **Extract unique repos**: Parse events for repo names you've interacted with
3. **Fetch details only for active repos**: Instead of 15k repos, fetch details for ~50-100

### Event Types That Indicate Activity

| Event Type | What It Means |
|------------|---------------|
| `PushEvent` | You pushed commits |
| `PullRequestEvent` | You opened/updated a PR |
| `PullRequestReviewEvent` | You reviewed a PR |
| `IssuesEvent` | You opened/closed an issue |
| `IssueCommentEvent` | You commented on an issue/PR |
| `CreateEvent` | You created a branch/tag |
| `CommitCommentEvent` | You commented on a commit |

### Implementation Plan

#### Phase 1: Core Events Fetching

```swift
// New method in GitHubRestAPI.swift
func userRecentActivityRepos(username: String, days: Int = 90) async throws -> [String] {
    let events = try await fetchAllPages(
        path: "/users/\(username)/events",
        queryItems: [],
        limit: 300,
        decode: { try GitHubDecoding.decode([GitHubEvent].self, from: $0) }
    )

    let cutoff = Date().addingTimeInterval(-Double(days * 24 * 60 * 60))
    let recentEvents = events.filter { $0.createdAt > cutoff }

    // Extract unique repo full names
    let repos = Set(recentEvents.map { $0.repo.name })
    return Array(repos)
}
```

#### Phase 2: New Fetch Mode

Add to `UserSettings`:
```swift
enum RepoFetchMode: String, Codable {
    case all           // Current behavior (fetch everything)
    case recentActivity // Events-based discovery
    case pinnedOnly    // Only fetch pinned repos
}
```

#### Phase 3: Smart Mode Selection

```swift
func activityRepositories(mode: RepoFetchMode) async throws -> [Repository] {
    switch mode {
    case .all:
        return try await restAPI.userReposPaginated(limit: nil)
    case .recentActivity:
        let username = try await currentUser().username
        let activeRepoNames = try await restAPI.userRecentActivityRepos(username: username)
        return try await fetchRepoDetails(for: activeRepoNames)
    case .pinnedOnly:
        return try await fetchRepoDetails(for: settings.pinnedRepositories)
    }
}
```

#### Phase 4: Auto-Detection

On first fetch, if >100 repos detected:
1. Show prompt: "You have access to many repositories. Switch to activity-based mode?"
2. Store preference
3. Default new enterprise accounts to `recentActivity` mode

### API Call Comparison

| Mode | API Calls | Time |
|------|-----------|------|
| All (15k repos) | 150+ pages + 30k detail calls | Minutes, rate limited |
| Events-based (~80 active repos) | 3 event pages + 160 detail calls | ~10 seconds |
| Pinned-only (10 repos) | 20 detail calls | ~2 seconds |

### Limitations

- Events API only covers last ~90 days
- Max 300 events returned (GitHub limit)
- Doesn't show repos you have access to but never touched
- Solution: Combine with pinned repos for "evergreen" repos

### UI Considerations

- Add picker in Settings > Advanced: "Repository discovery mode"
- Show explanation for each mode
- "Recent Activity" option with "(recommended for enterprise)" label
- Allow manual refresh to re-scan events

### Migration Path

1. Ship pinned-only mode first (simpler)
2. Add events-based mode as opt-in
3. Eventually make events-based the default for enterprise accounts
