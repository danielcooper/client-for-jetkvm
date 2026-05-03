import SwiftUI

@main
struct JetKVMApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        #if os(macOS)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Grant Accessibility Permission…") {
                    KeyboardManager.requestAccessibilityPermission()
                }
            }
        }
        #endif
    }
}

@Observable
final class AppState {
    var selectedDevice: KVMDevice?
    var isConnected = false
    /// Set to false when dialogs/sheets are open to pause KVM keyboard capture.
    var keyboardCaptureEnabled = true
}
