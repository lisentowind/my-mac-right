import AppKit

@MainActor
final class MacRightApplicationDelegate: NSObject, NSApplicationDelegate {
    private var requestNotificationObserver: NSObjectProtocol?
    private var nameWindowController: CreateFileNameWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestNotificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: SharedFileCreationStore.requestAvailableNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.presentPendingRequestIfNeeded()
            }
        }
        presentPendingRequestIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        presentPendingRequestIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentPendingRequestIfNeeded()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let requestNotificationObserver {
            DistributedNotificationCenter.default().removeObserver(requestNotificationObserver)
        }
        requestNotificationObserver = nil
    }

    private func presentPendingRequestIfNeeded() {
        SharedFileCreationStore.removeExpiredFiles()
        guard nameWindowController == nil,
              let request = SharedFileCreationStore.pendingRequests().first else {
            return
        }

        let controller = CreateFileNameWindowController(request: request) { [weak self] response in
            guard SharedFileCreationStore.writeResponse(response) else {
                NSLog("Mac Right could not return the file name to Finder Sync.")
                return
            }
            self?.nameWindowController = nil
            self?.presentPendingRequestIfNeeded()
        }
        nameWindowController = controller
        controller.showWindow(nil)
    }
}
