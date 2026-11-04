import Foundation

enum SharedPreferences {
    nonisolated static let suiteName = "group.tingfeng.my-mac-right.shared"

    static func writeFinderPreferences(_ preferences: FinderPreferencesSnapshot) {
        let url = finderPreferencesURL()
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Mac Right could not save Finder preferences: %@", error.localizedDescription)
        }
    }

    static func readFinderPreferences() -> FinderPreferencesSnapshot? {
        guard let data = try? Data(contentsOf: finderPreferencesURL()) else { return nil }
        return try? JSONDecoder().decode(FinderPreferencesSnapshot.self, from: data)
    }

    // 未沙箱化的扩展进程里 containerURL 返回 nil，只能按约定路径自己拼。
    static func finderPreferencesURL() -> URL {
        let fileName = "finder-preferences.json"
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) {
            return container.appendingPathComponent(fileName)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/\(suiteName)/\(fileName)")
    }
}

struct FinderFileCreationRequest: Codable, Identifiable {
    let id: UUID
    let type: FileTypeEntry
    let directoryPath: String?
    let createdAt: Date

    init(id: UUID = UUID(), type: FileTypeEntry, directoryPath: String?, createdAt: Date = Date()) {
        self.id = id
        self.type = type
        self.directoryPath = directoryPath
        self.createdAt = createdAt
    }
}

struct FinderFileCreationResponse: Codable {
    let requestID: UUID
    let fileName: String?
    let directoryPath: String?
    let createdFilePath: String?
    let isCancelled: Bool

    static func accepted(
        requestID: UUID,
        fileName: String,
        directoryPath: String?,
        createdFilePath: String? = nil
    ) -> FinderFileCreationResponse {
        FinderFileCreationResponse(
            requestID: requestID,
            fileName: fileName,
            directoryPath: directoryPath,
            createdFilePath: createdFilePath,
            isCancelled: false
        )
    }

    static func cancelled(requestID: UUID) -> FinderFileCreationResponse {
        FinderFileCreationResponse(
            requestID: requestID,
            fileName: nil,
            directoryPath: nil,
            createdFilePath: nil,
            isCancelled: true
        )
    }
}

enum SharedFileCreationStore {
    static let requestAvailableNotification = Notification.Name("tingfeng.my-mac-right.file-creation-request")

    private static let directoryName = "FinderFileCreation"
    private static let requestPrefix = "request-"
    private static let responsePrefix = "response-"
    private static let fileExtension = "json"

    static func writeRequest(_ request: FinderFileCreationRequest) -> Bool {
        let didWrite = write(request, to: requestURL(for: request.id))
        if didWrite {
            DistributedNotificationCenter.default().post(
                name: requestAvailableNotification,
                object: nil
            )
        }
        return didWrite
    }

    static func pendingRequests() -> [FinderFileCreationRequest] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.lastPathComponent.hasPrefix(requestPrefix) && $0.pathExtension == fileExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let request = try? JSONDecoder().decode(FinderFileCreationRequest.self, from: data),
                      !FileManager.default.fileExists(atPath: responseURL(for: request.id).path) else {
                    return nil
                }
                return request
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func response(for requestID: UUID) -> FinderFileCreationResponse? {
        let url = responseURL(for: requestID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FinderFileCreationResponse.self, from: data)
    }

    static func writeResponse(_ response: FinderFileCreationResponse) -> Bool {
        write(response, to: responseURL(for: response.requestID))
    }

    static func removeRequestAndResponse(for requestID: UUID) {
        try? FileManager.default.removeItem(at: requestURL(for: requestID))
        try? FileManager.default.removeItem(at: responseURL(for: requestID))
    }

    static func removeExpiredFiles(olderThan age: TimeInterval = 10 * 60) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL(),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let expirationDate = Date().addingTimeInterval(-age)
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedDate = values.contentModificationDate,
                  modifiedDate < expirationDate else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func write<Value: Encodable>(_ value: Value, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: directoryURL(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("Mac Right could not write file creation message: %@", error.localizedDescription)
            return false
        }
    }

    private static func directoryURL() -> URL {
        let directoryPath = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedPreferences.suiteName)
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/")
                .appendingPathComponent(SharedPreferences.suiteName)
        return directoryPath.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func requestURL(for requestID: UUID) -> URL {
        directoryURL().appendingPathComponent("\(requestPrefix)\(requestID.uuidString).\(fileExtension)")
    }

    private static func responseURL(for requestID: UUID) -> URL {
        directoryURL().appendingPathComponent("\(responsePrefix)\(requestID.uuidString).\(fileExtension)")
    }
}

enum FinderLaunchArguments {
    static let fileCreationRequest = "--finder-file-creation-request"
}

struct FinderPreferencesSnapshot: Codable {
    var fileTypes: [FileTypeEntry]
    var finderOpenWithBundleIdentifiers: Set<String>
    var showIcons: Bool
    var soundEnabled: Bool

    static let defaults = FinderPreferencesSnapshot(
        fileTypes: FileTypeEntry.defaults,
        finderOpenWithBundleIdentifiers: Set(FinderOpenWithApplication.supported.map(\.bundleIdentifier)),
        showIcons: true,
        soundEnabled: true
    )
}

enum FileExtensionPolicy {
    static func isValid(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-").contains(scalar)
        }
    }
}

enum DirectoryBookmark {
    static func create(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ data: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
        }
        return url
    }
}

struct FileTypeEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var isEnabled: Bool
    var iconName: String
    var displayName: String
    var fileExtension: String
    var isInMainMenu: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case iconName
        case displayName
        case fileExtension
        case isInMainMenu
    }

    init(
        id: UUID = UUID(),
        isEnabled: Bool = true,
        iconName: String = "doc.text",
        displayName: String,
        fileExtension: String,
        isInMainMenu: Bool = false
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.iconName = iconName
        self.displayName = displayName
        self.fileExtension = fileExtension
        self.isInMainMenu = isInMainMenu
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        iconName = try values.decodeIfPresent(String.self, forKey: .iconName) ?? "doc.text"
        displayName = try values.decode(String.self, forKey: .displayName)
        fileExtension = try values.decode(String.self, forKey: .fileExtension)
        isInMainMenu = try values.decodeIfPresent(Bool.self, forKey: .isInMainMenu) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(iconName, forKey: .iconName)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(fileExtension, forKey: .fileExtension)
        try values.encode(isInMainMenu, forKey: .isInMainMenu)
    }

    static let defaults: [FileTypeEntry] = [
        .init(iconName: "doc.text", displayName: "TXT", fileExtension: "txt"),
        .init(iconName: "doc.richtext", displayName: "RTF", fileExtension: "rtf"),
        .init(iconName: "chevron.left.forwardslash.chevron.right", displayName: "XML", fileExtension: "xml"),
        .init(iconName: "doc.fill", displayName: "Word", fileExtension: "docx"),
        .init(iconName: "tablecells", displayName: "Excel", fileExtension: "xlsx"),
        .init(iconName: "rectangle.on.rectangle", displayName: "PPT", fileExtension: "pptx"),
        .init(iconName: "doc.text", displayName: "WPS 文字", fileExtension: "wps"),
        .init(iconName: "tablecells", displayName: "WPS 表格", fileExtension: "et"),
        .init(iconName: "rectangle.on.rectangle", displayName: "WPS 演示", fileExtension: "dps"),
        .init(iconName: "doc.richtext", displayName: "Pages", fileExtension: "pages"),
        .init(iconName: "chart.bar", displayName: "Numbers", fileExtension: "numbers"),
        .init(iconName: "rectangle.on.rectangle", displayName: "Keynote", fileExtension: "key"),
        .init(iconName: "pencil.tip.crop.circle", displayName: "Ai", fileExtension: "ai"),
        .init(iconName: "photo", displayName: "PSD", fileExtension: "psd"),
        .init(iconName: "text.alignleft", displayName: "Markdown", fileExtension: "md")
    ]
}

struct FinderOpenWithApplication: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String
    let iconName: String

    var id: String { bundleIdentifier }

    static let supported: [FinderOpenWithApplication] = [
        .init(bundleIdentifier: "com.apple.Terminal", name: "终端", iconName: "terminal"),
        .init(bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code", iconName: "curlybraces")
    ]
}

struct FavoriteDirectory: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var path: String
    var bookmarkData: Data

    init(id: UUID = UUID(), name: String, path: String, bookmarkData: Data) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarkData = bookmarkData
    }
}
