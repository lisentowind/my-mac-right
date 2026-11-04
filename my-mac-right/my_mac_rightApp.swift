//
//  my_mac_rightApp.swift
//  my-mac-right
//
//  Created by tingfeng on 2026/11/3.
//

import AppKit
import SwiftUI

@main
struct my_mac_rightApp: App {
    @NSApplicationDelegateAdaptor(MacRightApplicationDelegate.self) private var applicationDelegate
    @StateObject private var preferences = PreferencesStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Mac Right", id: "main") {
            ContentView(store: preferences)
                .onAppear { NSApp.activate() }
        }

        MenuBarExtra("Mac Right", systemImage: "arrowshape.turn.up.right") {
            if let bookmark = preferences.creationDirectoryBookmark {
                Menu("新建文件") {
                    let enabledTypes = preferences.fileTypes.filter(\.isEnabled)
                    if enabledTypes.isEmpty {
                        Text("请在设置中启用文件格式")
                    } else {
                        ForEach(enabledTypes) { type in
                            Button("\(type.displayName) (.\(type.fileExtension))") {
                                createFile(type, in: bookmark)
                            }
                        }
                    }
                }
            } else {
                Button("先设置新文件保存位置") {
                    showMainWindow()
                }
            }

            if !preferences.favoriteDirectories.isEmpty {
                Menu("常用目录") {
                    ForEach(preferences.favoriteDirectories) { favorite in
                        Button(favorite.name) {
                            openDirectory(favorite)
                        }
                    }
                }
            }

            Divider()
            Button("打开 Mac Right") {
                showMainWindow()
            }
            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
    }

    private func createFile(_ type: FileTypeEntry, in bookmark: Data) {
        do {
            let url = try FileOperations.createFile(type: type, in: bookmark)
            if preferences.soundEnabled { NSSound(named: "Pop")?.play() }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func openDirectory(_ favorite: FavoriteDirectory) {
        do {
            _ = try FileOperations.withDirectoryAccess(favorite.bookmarkData) { url in
                NSWorkspace.shared.open(url)
            }
        } catch {
            showError("无法访问该目录：\(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "操作失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
