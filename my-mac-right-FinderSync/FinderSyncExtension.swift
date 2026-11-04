import AppKit
import FinderSync

final class FinderSyncExtension: FIFinderSync {
    private let controller = FIFinderSyncController.default()

    // Finder 会把返回的菜单归档后再回传，representedObject 到不了动作回调，
    // 所以菜单数据留在实例上，用 item.tag 关联。
    private var menuFileTypes: [FileTypeEntry] = []
    private var menuApplications: [FinderOpenWithApplication] = []
    private var menuDirectory: URL?
    private var menuSelectedItems: [URL] = []
    private var observedDirectories: [URL: Date] = [:]
    private var pendingResponseIDs: Set<UUID> = []

    override init() {
        super.init()
        controller.directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
    }

    override var toolbarItemName: String { "新建文件" }

    override var toolbarItemToolTip: String { "Mac Right：在当前位置新建文件" }

    override var toolbarItemImage: NSImage {
        let image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "新建文件")
            ?? NSImage(named: NSImage.addTemplateName)
            ?? NSImage(size: NSSize(width: 32, height: 32))
        image.isTemplate = true
        return image
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let storedPreferences = SharedPreferences.readFinderPreferences()
        let preferences = storedPreferences ?? .defaults
        let menu = NSMenu()
        let finderTypes = preferences.fileTypes.filter { $0.isEnabled && $0.isInMainMenu }
        let targetDirectory = currentTargetDirectory(for: menuKind)
        let selectedItems = menuKind == .contextualMenuForItems ? controller.selectedItemURLs() ?? [] : []

        if menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer || menuKind == .toolbarItemMenu {
            menuFileTypes = finderTypes
            menuDirectory = targetDirectory
            menuSelectedItems = selectedItems

            if menuKind == .toolbarItemMenu {
                addFileItems(
                    to: menu,
                    types: finderTypes,
                    preferences: preferences,
                    emptyMessage: "请在主应用选择 Finder 右键格式"
                )
            } else {
                let newFileItem = NSMenuItem(title: "新建文件", action: nil, keyEquivalent: "")
                let newFileSubmenu = NSMenu()
                if storedPreferences == nil {
                    newFileSubmenu.addItem(NSMenuItem(title: "设置未同步，请重新打开 Mac Right", action: nil, keyEquivalent: ""))
                } else {
                    addFileItems(
                        to: newFileSubmenu,
                        types: finderTypes,
                        preferences: preferences,
                        emptyMessage: "请在主应用选择 Finder 右键格式"
                    )
                }
                menu.setSubmenu(newFileSubmenu, for: newFileItem)
                menu.addItem(newFileItem)
            }

            let availableApplications = editorApplications(from: preferences)
            if !availableApplications.isEmpty {
                menuApplications = availableApplications
                let toolsItem = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
                setMenuImage(toolsItem, symbol: "wrench.and.screwdriver", enabled: preferences.showIcons)
                let submenu = NSMenu()
                for (index, application) in availableApplications.enumerated() {
                    let item = NSMenuItem(title: application.name, action: #selector(openInApplication(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = index
                    setMenuImage(item, symbol: application.iconName, enabled: preferences.showIcons)
                    submenu.addItem(item)
                }
                menu.setSubmenu(submenu, for: toolsItem)
                menu.addItem(toolsItem)
            }
        }

        return menu.items.isEmpty ? nil : menu
    }

    @objc private func createFile(_ sender: NSMenuItem) {
        // FinderSync 回调栈里不能起嵌套模态循环，UI 工作必须推到下一轮主循环。
        let tag = sender.tag
        DispatchQueue.main.async { [weak self] in
            self?.performCreate(tag: tag)
        }
    }

    private func performCreate(tag: Int) {
        guard menuFileTypes.indices.contains(tag) else {
            NSLog("Mac Right Finder Sync could not read the selected file type.")
            return
        }
        let type = menuFileTypes[tag]
        let directory = menuDirectory ?? controller.targetedURL()
        let request = FinderFileCreationRequest(
            type: type,
            directoryPath: directory?.standardizedFileURL.path
        )
        guard SharedFileCreationStore.writeRequest(request) else {
            NSLog("Mac Right Finder Sync could not send the file creation request.")
            return
        }

        openContainingApplication()
        waitForResponse(for: request)
    }

    @objc private func openInApplication(_ sender: NSMenuItem) {
        let tag = sender.tag
        DispatchQueue.main.async { [weak self] in
            self?.performOpen(tag: tag)
        }
    }

    private func performOpen(tag: Int) {
        guard menuApplications.indices.contains(tag),
              let appURL = NSWorkspace.shared.urlForApplication(
                  withBundleIdentifier: menuApplications[tag].bundleIdentifier
              ) else {
            showError("未找到所选应用。请在主应用的 Finder 菜单设置中重新检测。")
            return
        }
        let bundleIdentifier = menuApplications[tag].bundleIdentifier
        let directory = menuDirectory ?? controller.targetedURL()
        let selectedItems = menuSelectedItems
        let itemsToOpen: [URL]
        if bundleIdentifier == "com.apple.Terminal" {
            guard let directory = directory ?? chooseDirectory() else { return }
            itemsToOpen = [directory]
        } else if !selectedItems.isEmpty {
            itemsToOpen = selectedItems
        } else if let directory {
            itemsToOpen = [directory]
        } else {
            guard let directory = chooseDirectory() else { return }
            itemsToOpen = [directory]
        }
        let workspace = NSWorkspace.shared
        if bundleIdentifier == "com.apple.Terminal" {
            workspace.openApplication(at: appURL, configuration: .init()) { [weak self] application, error in
                guard application != nil, error == nil else {
                    self?.showOpenError(error?.localizedDescription ?? "终端未能启动。")
                    return
                }
                workspace.open(itemsToOpen, withApplicationAt: appURL, configuration: .init()) { [weak self] _, openError in
                    if let openError { self?.showOpenError(openError.localizedDescription) }
                }
            }
            return
        }
        workspace.open(itemsToOpen, withApplicationAt: appURL, configuration: .init()) { [weak self] application, error in
            guard application == nil || error != nil else { return }
            workspace.openApplication(at: appURL, configuration: .init()) { _, launchError in
                guard let launchError else { return }
                self?.showOpenError("无法打开 Visual Studio Code：\(launchError.localizedDescription)")
            }
        }
    }

    private func showOpenError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.showError(message)
        }
    }

    private func currentTargetDirectory(for menuKind: FIMenuKind) -> URL? {
        if let target = controller.targetedURL() {
            return isDirectory(target) ? target : target.deletingLastPathComponent()
        }
        if let selectedItem = controller.selectedItemURLs()?.first {
            return isDirectory(selectedItem) ? selectedItem : selectedItem.deletingLastPathComponent()
        }
        guard menuKind == .toolbarItemMenu else { return nil }
        return observedDirectories.max(by: { $0.value < $1.value })?.key
    }

    override func beginObservingDirectory(at url: URL) {
        observedDirectories[url.standardizedFileURL] = Date()
    }

    override func endObservingDirectory(at url: URL) {
        observedDirectories.removeValue(forKey: url.standardizedFileURL)
    }

    private func addFileItems(
        to menu: NSMenu,
        types: [FileTypeEntry],
        preferences: FinderPreferencesSnapshot,
        emptyMessage: String
    ) {
        if types.isEmpty {
            menu.addItem(NSMenuItem(title: emptyMessage, action: nil, keyEquivalent: ""))
            return
        }

        for (index, type) in types.enumerated() {
            let item = NSMenuItem(
                title: "\(type.displayName) (.\(type.fileExtension))",
                action: #selector(createFile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            setMenuImage(item, symbol: type.iconName, enabled: preferences.showIcons)
            menu.addItem(item)
        }
    }

    private func openContainingApplication() {
        let bundleIdentifier = "tingfeng.my-mac-right"
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else {
            return
        }

        let extensionBundleURL = Bundle(for: FinderSyncExtension.self).bundleURL
        guard let applicationURL = containingApplicationURL(for: extensionBundleURL)
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            NSLog("Mac Right could not locate its host application.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = [FinderLaunchArguments.fileCreationRequest]
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Mac Right could not open the host application: %@", error.localizedDescription)
            }
        }
    }

    private func containingApplicationURL(for extensionURL: URL) -> URL? {
        var candidate = extensionURL
        while candidate.pathExtension != "app" {
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { return nil }
            candidate = parent
        }
        return candidate
    }

    private func waitForResponse(for request: FinderFileCreationRequest) {
        guard pendingResponseIDs.insert(request.id).inserted else { return }
        pollForResponse(for: request, deadline: Date().addingTimeInterval(5 * 60))
    }

    private func pollForResponse(for request: FinderFileCreationRequest, deadline: Date) {
        if let response = SharedFileCreationStore.response(for: request.id) {
            pendingResponseIDs.remove(request.id)
            SharedFileCreationStore.removeRequestAndResponse(for: request.id)
            guard !response.isCancelled, let fileName = response.fileName else { return }

            if let createdFilePath = response.createdFilePath {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: createdFilePath)])
                return
            }

            let directoryPath = response.directoryPath ?? request.directoryPath
            guard let directoryPath else {
                NSLog("Mac Right Finder Sync received a file name without a directory.")
                return
            }
            let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
            do {
                let url = try FileOperations.createFile(type: request.type, named: fileName, in: directory)
                if SharedPreferences.readFinderPreferences()?.soundEnabled ?? true {
                    NSSound(named: "Pop")?.play()
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSLog("Mac Right could not create the file: %@", error.localizedDescription)
            }
            return
        }

        guard Date() < deadline else {
            pendingResponseIDs.remove(request.id)
            SharedFileCreationStore.removeRequestAndResponse(for: request.id)
            NSLog("Mac Right Finder Sync timed out waiting for a file name.")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pollForResponse(for: request, deadline: deadline)
        }
    }

    private func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选择要打开的文件夹"
        panel.prompt = "打开"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
    }

    private func showError(_ message: String) {
        NSLog("Mac Right Finder Sync: %@", message)
    }

    private func setMenuImage(_ item: NSMenuItem, symbol: String, enabled: Bool) {
        guard enabled else { return }
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.title)
    }

    private func editorApplications(from preferences: FinderPreferencesSnapshot) -> [FinderOpenWithApplication] {
        return FinderOpenWithApplication.supported.filter { application in
            preferences.finderOpenWithBundleIdentifiers.contains(application.bundleIdentifier)
                && NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier) != nil
        }
    }
}
