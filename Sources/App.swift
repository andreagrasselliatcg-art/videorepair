import SwiftUI
import AppKit

@main
struct VideoRepairApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("VideoRepair") {
            ContentView()
                .frame(minWidth: 680, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Plugin Finder: tasto destro > Servizi > "Ripara video con VideoRepair"
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    // "Apri con > VideoRepair" o trascinamento sull'icona nel Dock
    func application(_ application: NSApplication, open urls: [URL]) {
        DispatchQueue.main.async { RepairQueue.shared.add(urls) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Servizio richiamato dal Finder (NSMessage = repairVideos in Info.plist)
    @objc func repairVideos(_ pboard: NSPasteboard,
                            userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { RepairQueue.shared.add(urls) }
    }
}
