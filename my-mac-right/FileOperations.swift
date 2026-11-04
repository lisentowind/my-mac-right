import Foundation

struct TransferReport {
    var completed = 0
    var skipped = 0
    var failures: [String] = []
}

enum FileOperations {
    static func createFile(type: FileTypeEntry, named requestedName: String? = nil, in directoryBookmark: Data) throws -> URL {
        try withDirectoryAccess(directoryBookmark) { directory in
            try createFileInDirectory(type: type, named: requestedName, in: directory)
        }
    }

    static func createFile(type: FileTypeEntry, named requestedName: String? = nil, in directory: URL) throws -> URL {
        let didStartAccessing = directory.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        return try createFileInDirectory(type: type, named: requestedName, in: directory)
    }

    private static func createFileInDirectory(type: FileTypeEntry, named requestedName: String?, in directory: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: directory])
        }

        let name = (requestedName ?? type.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        let fileExtension = type.fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !name.isEmpty,
              name.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil,
              FileExtensionPolicy.isValid(fileExtension) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        var fileName = name
        if fileName.lowercased().hasSuffix(".\(fileExtension.lowercased())") {
            fileName.removeLast(fileExtension.count + 1)
        }
        guard !fileName.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }

        let url = uniqueURL(in: directory, name: fileName, extension: fileExtension)
        try starterContent(for: fileExtension).write(to: url, options: .withoutOverwriting)
        return url
    }

    static func transfer(items: [URL], to destinationBookmark: Data, move: Bool) throws -> TransferReport {
        try withDirectoryAccess(destinationBookmark) { destination in
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSURLErrorKey: destination])
            }

            var report = TransferReport()
            for item in items {
                let didStartSourceAccess = item.startAccessingSecurityScopedResource()
                defer {
                    if didStartSourceAccess {
                        item.stopAccessingSecurityScopedResource()
                    }
                }

                let source = item.standardizedFileURL
                let normalizedDestination = destination.standardizedFileURL
                let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let itemName = isDirectory ? item.lastPathComponent : item.deletingPathExtension().lastPathComponent
                if move && source.deletingLastPathComponent() == normalizedDestination {
                    report.skipped += 1
                    continue
                }
                if isDirectory,
                   (normalizedDestination == source || normalizedDestination.path.hasPrefix(source.path + "/")) {
                    report.failures.append("\(item.lastPathComponent)：不能将文件夹复制或移动到自身内部。")
                    continue
                }
                let target = uniqueURL(in: destination, name: itemName, extension: isDirectory ? "" : item.pathExtension)

                do {
                    if move {
                        try FileManager.default.moveItem(at: item, to: target)
                    } else {
                        try FileManager.default.copyItem(at: item, to: target)
                    }
                    report.completed += 1
                } catch {
                    report.failures.append("\(item.lastPathComponent)：\(error.localizedDescription)")
                }
            }
            return report
        }
    }

    static func withDirectoryAccess<Value>(_ bookmark: Data, perform action: (URL) throws -> Value) throws -> Value {
        let url = try DirectoryBookmark.resolve(bookmark)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try action(url)
    }

    private static func uniqueURL(in directory: URL, name: String, extension fileExtension: String) -> URL {
        let fileManager = FileManager.default
        var suffix = 1
        var candidate: URL
        repeat {
            let candidateName = suffix == 1 ? name : "\(name) \(suffix)"
            let fileURL = directory.appendingPathComponent(candidateName)
            candidate = fileExtension.isEmpty ? fileURL : fileURL.appendingPathExtension(fileExtension)
            suffix += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    private static func starterContent(for fileExtension: String) -> Data {
        let content: String
        switch fileExtension.lowercased() {
        case "rtf":
            content = "{\\rtf1\\ansi\\deff0\n}"
        case "xml":
            content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        case "md", "markdown":
            content = ""
        default:
            content = ""
        }
        return Data(content.utf8)
    }
}
