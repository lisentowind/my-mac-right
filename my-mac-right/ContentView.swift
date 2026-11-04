import AppKit
import FinderSync
import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case newFile = "新建文件"
    case transfer = "复制 / 移动"
    case favorites = "常用目录"
    case fileTypes = "文件格式"
    case finderMenu = "Finder 菜单"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .newFile: "doc.badge.plus"
        case .transfer: "arrow.right.doc.on.clipboard"
        case .favorites: "heart"
        case .fileTypes: "list.bullet.rectangle"
        case .finderMenu: "menubar.rectangle"
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: PreferencesStore
    @State private var selection: AppSection? = .newFile

    var body: some View {
        NavigationSplitView {
            List {
                Section("我的 Mac Right") {
                    ForEach(AppSection.allCases) { section in
                        Button {
                            selection = section
                        } label: {
                            Label(section.rawValue, systemImage: section.symbol)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selection == section ? Color.accentColor.opacity(0.13) : Color.clear)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 205)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("显示图标", isOn: $store.showIcons)
                    Toggle("开启提示音", isOn: $store.soundEnabled)
                    Divider()
                    Button {
                        FIFinderSyncController.showExtensionManagementInterface()
                    } label: {
                        Label(
                            FIFinderSyncController.isExtensionEnabled ? "管理 Finder 扩展" : "启用 Finder 扩展",
                            systemImage: FIFinderSyncController.isExtensionEnabled ? "checkmark.circle" : "puzzlepiece.extension"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .font(.callout)
                .padding(14)
            }
        } detail: {
            Group {
                switch selection ?? .newFile {
                case .newFile:
                    NewFileView(store: store)
                case .transfer:
                    TransferView(store: store)
                case .favorites:
                    FavoritesView(store: store)
                case .fileTypes:
                    FileTypesView(store: store)
                case .finderMenu:
                    FinderMenuView(store: store)
                }
            }
            .frame(minWidth: 560, minHeight: 440)
        }
        .frame(minWidth: 790, minHeight: 560)
    }
}

private struct NewFileView: View {
    @ObservedObject var store: PreferencesStore
    @State private var selectedTypeID: UUID?
    @State private var fileName = "TXT"
    @State private var destinationBookmark: Data?
    @State private var destinationName = "尚未选择"
    @State private var message: OperationMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "新建文件", subtitle: "选择格式和保存位置，快速创建空白文件。", symbol: "doc.badge.plus")

            GroupBox("保存位置") {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(destinationName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("选择文件夹…", systemImage: "folder.badge.plus") {
                        chooseDestination()
                    }
                }
                .padding(.vertical, 4)
            }

            Text("文件格式")
                .font(.headline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(store.fileTypes.filter(\.isEnabled)) { type in
                        Button {
                            selectedTypeID = type.id
                            fileName = type.displayName
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: store.showIcons ? type.iconName : "doc")
                                    .font(.title3)
                                    .frame(width: 26)
                                    .foregroundStyle(selectedTypeID == type.id ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(type.displayName)
                                        .fontWeight(.medium)
                                    Text(".\(type.fileExtension)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if selectedTypeID == type.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTypeID == type.id ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(selectedTypeID == type.id ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.35))
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            if let selectedType {
                HStack(spacing: 8) {
                    Text("文件名")
                        .foregroundStyle(.secondary)
                    TextField("输入文件名", text: $fileName)
                        .textFieldStyle(.roundedBorder)
                    Text(".\(selectedType.fileExtension)")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if let message {
                    Label(message.text, systemImage: message.isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(message.isError ? Color.orange : Color.secondary)
                        .font(.callout)
                        .lineLimit(2)
                }
                Spacer()
                Button("新建文件", systemImage: "plus") {
                    createFile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedType == nil || destinationBookmark == nil)
            }
        }
        .padding(22)
        .onAppear {
            if selectedTypeID == nil {
                let firstType = store.fileTypes.first(where: \.isEnabled)
                selectedTypeID = firstType?.id
                fileName = firstType?.displayName ?? ""
            }
            if destinationBookmark == nil, let bookmark = store.creationDirectoryBookmark {
                destinationBookmark = bookmark
                destinationName = (try? FileOperations.withDirectoryAccess(bookmark) { $0.path }) ?? "上次保存位置"
            }
        }
        .onChange(of: store.fileTypes) { _, types in
            if !types.contains(where: { $0.id == selectedTypeID && $0.isEnabled }) {
                let firstType = types.first(where: \.isEnabled)
                selectedTypeID = firstType?.id
                fileName = firstType?.displayName ?? ""
            }
        }
    }

    private var selectedType: FileTypeEntry? {
        store.fileTypes.first { $0.id == selectedTypeID && $0.isEnabled }
    }

    private func chooseDestination() {
        guard let url = PanelUtilities.chooseDirectory(message: "选择新文件的保存位置") else { return }
        do {
            try store.setCreationDirectory(url: url)
            destinationBookmark = store.creationDirectoryBookmark
            destinationName = url.path
            message = nil
        } catch {
            message = .init(text: error.localizedDescription, isError: true)
        }
    }

    private func createFile() {
        guard let selectedType, let destinationBookmark else { return }
        do {
            let url = try FileOperations.createFile(type: selectedType, named: fileName, in: destinationBookmark)
            message = .init(text: "已创建 \(url.lastPathComponent)", isError: false)
            if store.soundEnabled { NSSound(named: "Pop")?.play() }
        } catch {
            message = .init(text: error.localizedDescription, isError: true)
        }
    }
}

private struct TransferView: View {
    @ObservedObject var store: PreferencesStore
    @State private var selectedItems: [URL] = []
    @State private var destinationBookmark: Data?
    @State private var destinationName = "尚未选择"
    @State private var shouldMove = false
    @State private var message: OperationMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "复制 / 移动", subtitle: "将文件或文件夹一次性发送到指定目录。", symbol: "arrow.right.doc.on.clipboard")

            GroupBox("要处理的项目") {
                VStack(alignment: .leading, spacing: 8) {
                    if selectedItems.isEmpty {
                        ContentUnavailableView("尚未选择项目", systemImage: "doc.on.doc", description: Text("可以一次选择多个文件或文件夹。"))
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(selectedItems, id: \.standardizedFileURL) { item in
                            HStack(spacing: 8) {
                                Image(systemName: FileManager.default.fileExists(atPath: item.path) ? "doc" : "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                                Text(item.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                        }
                    }
                    HStack {
                        Spacer()
                        Button("选择项目…", systemImage: "plus") {
                            if let items = PanelUtilities.chooseItems() {
                                selectedItems = items
                                message = nil
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("目标位置") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(destinationName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("选择文件夹…", systemImage: "folder.badge.plus") {
                            chooseDestination()
                        }
                    }
                    if !store.favoriteDirectories.isEmpty {
                        HStack {
                            Text("常用")
                                .foregroundStyle(.secondary)
                            ForEach(store.favoriteDirectories) { favorite in
                                Button(favorite.name) {
                                    destinationBookmark = favorite.bookmarkData
                                    destinationName = favorite.path
                                    message = nil
                                }
                                .buttonStyle(.link)
                            }
                        }
                        .font(.callout)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Picker("操作", selection: $shouldMove) {
                    Text("复制").tag(false)
                    Text("移动").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer()
                if let message {
                    Label(message.text, systemImage: message.isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(message.isError ? Color.orange : Color.secondary)
                        .font(.callout)
                        .lineLimit(2)
                }
                Spacer()
                Button(shouldMove ? "移动" : "复制", systemImage: shouldMove ? "arrow.right" : "doc.on.doc") {
                    performTransfer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItems.isEmpty || destinationBookmark == nil)
            }
        }
        .padding(22)
    }

    private func chooseDestination() {
        guard let url = PanelUtilities.chooseDirectory(message: "选择目标文件夹") else { return }
        do {
            let bookmark = try DirectoryBookmark.create(for: url)
            destinationBookmark = bookmark
            destinationName = url.path
            message = nil
        } catch {
            message = .init(text: error.localizedDescription, isError: true)
        }
    }

    private func performTransfer() {
        guard let destinationBookmark else { return }
        do {
            let report = try FileOperations.transfer(items: selectedItems, to: destinationBookmark, move: shouldMove)
            selectedItems.removeAll { url in
                shouldMove && !FileManager.default.fileExists(atPath: url.path)
            }
            let action = shouldMove ? "移动" : "复制"
            if report.failures.isEmpty {
                let skipped = report.skipped > 0 ? "，跳过 \(report.skipped) 个" : ""
                message = .init(text: "已\(action) \(report.completed) 个项目\(skipped)。", isError: false)
            } else {
                let skipped = report.skipped > 0 ? "，跳过 \(report.skipped) 个" : ""
                message = .init(text: "完成 \(report.completed) 个，失败 \(report.failures.count) 个\(skipped)：\(report.failures.prefix(2).joined(separator: "；"))", isError: true)
            }
            if report.completed > 0, store.soundEnabled { NSSound(named: "Pop")?.play() }
        } catch {
            message = .init(text: error.localizedDescription, isError: true)
        }
    }
}

private struct FavoritesView: View {
    @ObservedObject var store: PreferencesStore
    @State private var message: OperationMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeading(title: "常用目录", subtitle: "保存经常访问的位置，供文件操作快速选用。", symbol: "heart")

            HStack {
                Spacer()
                Button("添加目录…", systemImage: "folder.badge.plus") {
                    addDirectory()
                }
            }

            if store.favoriteDirectories.isEmpty {
                ContentUnavailableView("还没有常用目录", systemImage: "folder.badge.heart", description: Text("添加文件夹后，可在复制和移动操作中快速选用。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.favoriteDirectories) { favorite in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(favorite.name)
                                    .fontWeight(.medium)
                                Text(favorite.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("打开", systemImage: "arrow.up.right.square") {
                                openDirectory(favorite)
                            }
                            .labelStyle(.iconOnly)
                            .help("在 Finder 中打开目录")
                            Button("移除", systemImage: "minus.circle") {
                                store.removeFavoriteDirectory(id: favorite.id)
                            }
                            .labelStyle(.iconOnly)
                            .help("从常用目录中移除")
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }

            if let message {
                Label(message.text, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
        }
        .padding(22)
    }

    private func addDirectory() {
        guard let url = PanelUtilities.chooseDirectory(message: "添加常用目录") else { return }
        do {
            try store.addFavoriteDirectory(url: url)
            message = nil
        } catch {
            message = .init(text: error.localizedDescription, isError: true)
        }
    }

    private func openDirectory(_ favorite: FavoriteDirectory) {
        do {
            _ = try FileOperations.withDirectoryAccess(favorite.bookmarkData) { url in
                NSWorkspace.shared.open(url)
            }
            message = nil
        } catch {
            message = .init(text: "无法访问该目录：\(error.localizedDescription)", isError: true)
        }
    }
}

private struct FileTypesView: View {
    @ObservedObject var store: PreferencesStore
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeading(title: "文件格式", subtitle: "选择 Finder 右键菜单中的新建格式，并管理名称与后缀。", symbol: "list.bullet.rectangle")

            Table(store.fileTypes, selection: $selectedIDs) {
                TableColumn("启用") { type in
                    Toggle("", isOn: Binding(
                        get: { current(type.id)?.isEnabled ?? false },
                        set: { value in update(type.id) { $0.isEnabled = value } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                }
                .width(48)
                TableColumn("图标") { type in
                    Image(systemName: type.iconName)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .width(48)
                TableColumn("显示名称") { type in
                    TextField("名称", text: textBinding(for: type.id, keyPath: \.displayName))
                        .textFieldStyle(.plain)
                }
                .width(min: 120, ideal: 180)
                TableColumn("后缀") { type in
                    TextField("后缀", text: textBinding(for: type.id, keyPath: \.fileExtension))
                        .textFieldStyle(.plain)
                }
                .width(min: 70, ideal: 100)
                TableColumn("Finder 右键") { type in
                    Toggle("", isOn: Binding(
                        get: { current(type.id)?.isInMainMenu ?? false },
                        set: { value in update(type.id) { $0.isInMainMenu = value } }
                    ))
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                }
                .width(min: 85, ideal: 100)
            }
            .alternatingRowBackgrounds()

            HStack(spacing: 8) {
                Button("添加格式", systemImage: "plus") {
                    showingAddSheet = true
                }
                .help("添加自定义文件格式")
                Button("移除格式", systemImage: "minus") {
                    store.removeFileTypes(withIDs: selectedIDs)
                    selectedIDs.removeAll()
                }
                .disabled(selectedIDs.isEmpty)
                Button("上移", systemImage: "arrow.up") {
                    moveSelectedType(by: -1)
                }
                .disabled(!canMoveSelectedType(by: -1))
                .help("上移所选格式")
                Button("下移", systemImage: "arrow.down") {
                    moveSelectedType(by: 1)
                }
                .disabled(!canMoveSelectedType(by: 1))
                .help("下移所选格式")
                Spacer()
                Button("重置默认", systemImage: "arrow.counterclockwise") {
                    store.resetFileTypes()
                    selectedIDs.removeAll()
                }
            }

            Text("只有同时启用并勾选“Finder 右键”的格式才会显示在 Finder 新建菜单中。专有格式目前创建空文件。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .sheet(isPresented: $showingAddSheet) {
            AddFileTypeSheet(store: store)
        }
    }

    private func current(_ id: UUID) -> FileTypeEntry? {
        store.fileTypes.first { $0.id == id }
    }

    private func update(_ id: UUID, change: (inout FileTypeEntry) -> Void) {
        guard var type = current(id) else { return }
        change(&type)
        store.update(type)
    }

    private func canMoveSelectedType(by offset: Int) -> Bool {
        guard selectedIDs.count == 1,
              let selectedID = selectedIDs.first,
              let index = store.fileTypes.firstIndex(where: { $0.id == selectedID }) else { return false }
        return store.fileTypes.indices.contains(index + offset)
    }

    private func moveSelectedType(by offset: Int) {
        guard selectedIDs.count == 1,
              let selectedID = selectedIDs.first,
              let index = store.fileTypes.firstIndex(where: { $0.id == selectedID }) else { return }
        let destination = index + offset
        guard store.fileTypes.indices.contains(destination) else { return }
        store.moveFileTypes(from: IndexSet(integer: index), to: destination > index ? destination + 1 : destination)
    }

    private func textBinding(for id: UUID, keyPath: WritableKeyPath<FileTypeEntry, String>) -> Binding<String> {
        Binding(
            get: { current(id)?[keyPath: keyPath] ?? "" },
            set: { value in
                if keyPath == \.fileExtension {
                    let normalized = value
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        .lowercased()
                    guard normalized.isEmpty || FileExtensionPolicy.isValid(normalized) else { return }
                    guard !store.fileTypes.contains(where: {
                        $0.id != id && $0.fileExtension.caseInsensitiveCompare(normalized) == .orderedSame
                    }) else { return }
                    update(id) { $0[keyPath: keyPath] = normalized }
                } else {
                    update(id) { $0[keyPath: keyPath] = value }
                }
            }
        )
    }
}

private struct FinderMenuView: View {
    @ObservedObject var store: PreferencesStore
    @State private var installedBundleIdentifiers: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                PageHeading(title: "Finder 菜单", subtitle: "选择 Finder“打开方式”中显示的应用。", symbol: "menubar.rectangle")
                Spacer()
                Button {
                    refreshInstalledApplications()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("重新检测应用")
            }

            GroupBox("打开方式") {
                VStack(spacing: 0) {
                    ForEach(FinderOpenWithApplication.supported) { application in
                        HStack(spacing: 12) {
                            Image(systemName: application.iconName)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            Text(application.name)
                            Text(installedBundleIdentifiers.contains(application.bundleIdentifier) ? "已安装" : "未检测到")
                                .font(.callout)
                                .foregroundStyle(installedBundleIdentifiers.contains(application.bundleIdentifier) ? Color.secondary : Color.orange)
                            Spacer()
                            Toggle(application.name, isOn: Binding(
                                get: { store.finderOpenWithBundleIdentifiers.contains(application.bundleIdentifier) },
                                set: { store.setFinderOpenWith(application, enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            .disabled(!installedBundleIdentifiers.contains(application.bundleIdentifier))
                        }
                        .padding(.vertical, 8)
                        if application.id != FinderOpenWithApplication.supported.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Text("只有已安装且勾选的应用会出现在 Finder 右键菜单的“打开方式”中。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(22)
        .onAppear(perform: refreshInstalledApplications)
    }

    private func refreshInstalledApplications() {
        installedBundleIdentifiers = Set(FinderOpenWithApplication.supported.compactMap { application in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier) == nil
                ? nil
                : application.bundleIdentifier
        })
    }
}

private struct AddFileTypeSheet: View {
    @ObservedObject var store: PreferencesStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var fileExtension = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("添加自定义格式")
                .font(.title2.weight(.semibold))
            TextField("显示名称", text: $name)
            TextField("文件后缀，例如 log", text: $fileExtension)
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") { add() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func add() {
        if let error = store.addFileType(name: name, fileExtension: fileExtension) {
            errorMessage = error
        } else {
            dismiss()
        }
    }
}

private struct PageHeading: View {
    var title: String
    var subtitle: String
    var symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }
}

private struct OperationMessage {
    var text: String
    var isError: Bool
}
