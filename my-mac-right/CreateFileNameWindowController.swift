import AppKit

@MainActor
final class CreateFileNameWindowController: NSWindowController, NSWindowDelegate {
    private let request: FinderFileCreationRequest
    private let completion: (FinderFileCreationResponse) -> Void
    private let nameField: NSTextField
    private let errorLabel = NSTextField(labelWithString: "")
    private var didFinish = false

    init(
        request: FinderFileCreationRequest,
        completion: @escaping (FinderFileCreationResponse) -> Void
    ) {
        self.request = request
        self.completion = completion
        nameField = NSTextField(string: request.type.displayName)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "新建 \(request.type.displayName) 文件"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        configureWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("CreateFileNameWindowController does not support storyboards")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        activateAndFocusNameField()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(with: .cancelled(requestID: request.id))
        return true
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "文件名")
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        nameField.placeholderString = "输入文件名"
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.isEnabled = true
        nameField.target = self
        nameField.action = #selector(createFile)
        nameField.focusRingType = .default

        let extensionLabel = NSTextField(labelWithString: "扩展名：.\(request.type.fileExtension)")
        extensionLabel.textColor = .secondaryLabelColor

        let locationLabel = NSTextField(
            labelWithString: request.directoryPath.map { "位置：\($0)" } ?? "位置：点击创建后选择文件夹"
        )
        locationLabel.textColor = .secondaryLabelColor
        locationLabel.lineBreakMode = .byTruncatingMiddle

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.lineBreakMode = .byTruncatingTail

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelButton.keyEquivalent = "\u{1b}"

        let createButton = NSButton(title: "创建", target: self, action: #selector(createFile))
        createButton.bezelStyle = .rounded
        createButton.keyEquivalent = "\r"

        for view in [titleLabel, nameField, extensionLabel, locationLabel, errorLabel, cancelButton, createButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),

            nameField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            nameField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            nameField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            nameField.heightAnchor.constraint(equalToConstant: 28),

            extensionLabel.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            extensionLabel.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 7),

            locationLabel.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            locationLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            locationLabel.topAnchor.constraint(equalTo: extensionLabel.bottomAnchor, constant: 4),

            errorLabel.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            errorLabel.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: 4),

            cancelButton.trailingAnchor.constraint(equalTo: createButton.leadingAnchor, constant: -8),
            cancelButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            createButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            createButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            createButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])

        window?.initialFirstResponder = nameField
    }

    private func activateAndFocusNameField() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            NSApp.activate()
            window.makeKey()
            window.makeFirstResponder(self.nameField)
            self.nameField.selectText(nil)
        }
    }

    @objc private func createFile() {
        let fileName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else {
            NSSound.beep()
            activateAndFocusNameField()
            return
        }
        guard fileName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else {
            NSSound.beep()
            activateAndFocusNameField()
            return
        }

        var directoryPath = request.directoryPath
        if directoryPath == nil {
            guard let directory = PanelUtilities.chooseDirectory(message: "选择新文件保存位置") else {
                activateAndFocusNameField()
                return
            }
            directoryPath = directory.standardizedFileURL.path

            do {
                let createdFile = try FileOperations.createFile(
                    type: request.type,
                    named: fileName,
                    in: directory
                )
                finish(with: .accepted(
                    requestID: request.id,
                    fileName: fileName,
                    directoryPath: directoryPath,
                    createdFilePath: createdFile.path
                ))
            } catch {
                errorLabel.stringValue = "创建失败：\(error.localizedDescription)"
                activateAndFocusNameField()
            }
            return
        }

        finish(with: .accepted(
            requestID: request.id,
            fileName: fileName,
            directoryPath: directoryPath
        ))
    }

    @objc private func cancel() {
        finish(with: .cancelled(requestID: request.id))
    }

    private func finish(with response: FinderFileCreationResponse) {
        guard !didFinish else { return }
        didFinish = true
        completion(response)
        close()
    }
}
