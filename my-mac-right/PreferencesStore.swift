import Foundation
import Combine

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var fileTypes: [FileTypeEntry] {
        didSet {
            save(fileTypes, forKey: Key.fileTypes)
            writeFinderPreferences()
        }
    }

    @Published var favoriteDirectories: [FavoriteDirectory] {
        didSet { save(favoriteDirectories, forKey: Key.favoriteDirectories) }
    }

    @Published var creationDirectoryBookmark: Data? {
        didSet { set(creationDirectoryBookmark, forKey: Key.creationDirectoryBookmark) }
    }

    @Published var showIcons: Bool {
        didSet {
            set(showIcons, forKey: Key.showIcons)
            writeFinderPreferences()
        }
    }

    @Published var soundEnabled: Bool {
        didSet {
            set(soundEnabled, forKey: Key.soundEnabled)
            writeFinderPreferences()
        }
    }

    @Published var finderOpenWithBundleIdentifiers: Set<String> {
        didSet {
            save(finderOpenWithBundleIdentifiers, forKey: Key.finderOpenWithBundleIdentifiers)
            writeFinderPreferences()
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: SharedPreferences.suiteName) ?? .standard) {
        self.defaults = defaults
        fileTypes = Self.load([FileTypeEntry].self, forKey: Key.fileTypes, from: defaults) ?? FileTypeEntry.defaults
        favoriteDirectories = Self.load([FavoriteDirectory].self, forKey: Key.favoriteDirectories, from: defaults) ?? []
        creationDirectoryBookmark = defaults.data(forKey: Key.creationDirectoryBookmark)
        showIcons = defaults.object(forKey: Key.showIcons) as? Bool ?? true
        soundEnabled = defaults.object(forKey: Key.soundEnabled) as? Bool ?? true
        finderOpenWithBundleIdentifiers = Self.load(Set<String>.self, forKey: Key.finderOpenWithBundleIdentifiers, from: defaults)
            ?? Set(FinderOpenWithApplication.supported.map(\.bundleIdentifier))
        writeFinderPreferences()
    }

    func update(_ fileType: FileTypeEntry) {
        guard let index = fileTypes.firstIndex(where: { $0.id == fileType.id }) else { return }
        fileTypes[index] = fileType
    }

    func addFileType(name: String, fileExtension: String) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExtension = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        guard !cleanName.isEmpty, !cleanExtension.isEmpty else {
            return "名称和后缀不能为空。"
        }
        guard FileExtensionPolicy.isValid(cleanExtension),
              cleanName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else {
            return "名称或后缀包含无效字符。"
        }
        guard !fileTypes.contains(where: { $0.fileExtension.caseInsensitiveCompare(cleanExtension) == .orderedSame }) else {
            return "这个后缀已经存在。"
        }

        fileTypes.append(.init(displayName: cleanName, fileExtension: cleanExtension))
        return nil
    }

    func removeFileTypes(withIDs ids: Set<UUID>) {
        fileTypes.removeAll { ids.contains($0.id) }
    }

    func moveFileTypes(from source: IndexSet, to destination: Int) {
        let sourceIndices = source.filter { fileTypes.indices.contains($0) }
        let moving = sourceIndices.map { fileTypes[$0] }
        let removedBeforeDestination = sourceIndices.filter { $0 < destination }.count
        for index in sourceIndices.reversed() {
            fileTypes.remove(at: index)
        }
        let insertionIndex = min(max(destination - removedBeforeDestination, 0), fileTypes.count)
        fileTypes.insert(contentsOf: moving, at: insertionIndex)
    }

    func resetFileTypes() {
        fileTypes = FileTypeEntry.defaults
    }

    func addFavoriteDirectory(url: URL) throws {
        let normalizedURL = url.standardizedFileURL
        guard !favoriteDirectories.contains(where: { $0.path == normalizedURL.path }) else { return }
        let bookmark = try DirectoryBookmark.create(for: normalizedURL)
        favoriteDirectories.append(.init(
            name: normalizedURL.lastPathComponent.isEmpty ? normalizedURL.path : normalizedURL.lastPathComponent,
            path: normalizedURL.path,
            bookmarkData: bookmark
        ))
    }

    func removeFavoriteDirectory(id: UUID) {
        favoriteDirectories.removeAll { $0.id == id }
    }

    func setCreationDirectory(url: URL) throws {
        creationDirectoryBookmark = try DirectoryBookmark.create(for: url.standardizedFileURL)
    }

    func setFinderOpenWith(_ application: FinderOpenWithApplication, enabled: Bool) {
        if enabled {
            finderOpenWithBundleIdentifiers.insert(application.bundleIdentifier)
        } else {
            finderOpenWithBundleIdentifiers.remove(application.bundleIdentifier)
        }
    }

    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }

    private func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }

    private func writeFinderPreferences() {
        SharedPreferences.writeFinderPreferences(.init(
            fileTypes: fileTypes,
            finderOpenWithBundleIdentifiers: finderOpenWithBundleIdentifiers,
            showIcons: showIcons,
            soundEnabled: soundEnabled
        ))
    }

    private static func load<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String,
        from defaults: UserDefaults
    ) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private enum Key {
        static let fileTypes = "preferences.fileTypes"
        static let favoriteDirectories = "preferences.favoriteDirectories"
        static let creationDirectoryBookmark = "preferences.creationDirectoryBookmark"
        static let showIcons = "preferences.showIcons"
        static let soundEnabled = "preferences.soundEnabled"
        static let finderOpenWithBundleIdentifiers = "preferences.finderOpenWithBundleIdentifiers"
    }
}
