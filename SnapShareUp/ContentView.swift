import SwiftUI
import CoreGraphics
import UserNotifications
import AppKit

struct ContentView: View {
    @EnvironmentObject private var configManager: ConfigurationManager
    @StateObject private var captureHandler: CaptureHandler
    
    init(configManager: ConfigurationManager) {
        // Initialize with the actual ConfigurationManager
        _captureHandler = StateObject(wrappedValue: CaptureHandler(configManager: configManager))
    }
    
    var body: some View {
        EmptyView()
            .onAppear {
                requestScreenCapturePermission()
            }
    }
    
    private func requestScreenCapturePermission() {
        if CGPreflightScreenCaptureAccess() == false {
            CGRequestScreenCaptureAccess()
            
            let alert = NSAlert()
            alert.messageText = "Screen Recording Permission Required"
            alert.informativeText = "Please enable screen recording permission in System Preferences > Security & Privacy > Privacy > Screen Recording, then restart the app."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Preferences")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
