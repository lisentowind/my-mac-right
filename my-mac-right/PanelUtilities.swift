import AppKit
import Foundation

enum PanelUtilities {
    static func chooseDirectory(message: String = "请选择一个文件夹") -> URL? {
        let panel = NSOpenPanel()
        panel.title = message
        panel.prompt = "选择"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseItems() -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "选择要处理的文件或文件夹"
        panel.prompt = "继续"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        return panel.runModal() == .OK ? panel.urls : nil
    }
}
