import Foundation

public struct SavedFolder: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let path: String
    private let bookmark: Data?

    public init(url: URL) {
        id = UUID()
        let url = url.standardizedFileURL.resolvingSymlinksInPath()
        path = url.path
        bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public var url: URL {
        if let bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return resolved
            }
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var sources: [SavedFolder]
    public var destination: SavedFolder?

    public init(sources: [SavedFolder] = [], destination: SavedFolder? = nil) {
        self.sources = sources
        self.destination = destination
    }
}

public final class PreferencesStore {
    private let defaults: UserDefaults
    private let key = "folderPreferences.v1"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(AppPreferences.self, from: data) else { return AppPreferences() }
        return value
    }

    public func save(_ preferences: AppPreferences) throws {
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}
