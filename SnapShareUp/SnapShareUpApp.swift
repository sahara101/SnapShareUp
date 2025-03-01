import SwiftUI
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let configManager = ConfigurationManager()
    lazy var captureHandler = CaptureHandler(configManager: configManager)
    lazy var videoCaptureHandler = VideoCaptureHandler(configManager: configManager)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        // Set the delegate first
        UNUserNotificationCenter.current().delegate = self
        
        // Then request authorization with proper error handling
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied: \(error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // This method allows notifications to appear even when the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    // This method handles notification interaction when the app is not in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification response if needed
        completionHandler()
    }
}

@main
struct SnapShareUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private func createTemplateImage() -> Image {
        if let appIcon = NSImage(named: "AppIcon") {
            let templateImage = NSImage(size: NSSize(width: 18, height: 18))
            templateImage.isTemplate = true
            
            if let templateData = appIcon.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: templateData) {
                templateImage.addRepresentation(bitmap)
            }
            
            return Image(nsImage: templateImage)
        }
        return Image(systemName: "camera")
    }
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                captureHandler: appDelegate.captureHandler,
                videoCaptureHandler: appDelegate.videoCaptureHandler
            )
            .environmentObject(appDelegate.configManager)
        } label: {
            createTemplateImage()
        }
        
        Settings {
            NavigationStack {
                PreferencesView()
                    .environmentObject(appDelegate.configManager)
                    .frame(minWidth: 800, minHeight: 500)
            }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var configManager: ConfigurationManager
    
    // Direct references to handlers passed as parameters
    let captureHandler: CaptureHandler
    let videoCaptureHandler: VideoCaptureHandler
    
    init(captureHandler: CaptureHandler, videoCaptureHandler: VideoCaptureHandler) {
        print("MenuBarView: Initializing with direct handler references")
        self.captureHandler = captureHandler
        self.videoCaptureHandler = videoCaptureHandler
    }
    
    var body: some View {
        Group {
            if let currentConfig = configManager.selectedConfig {
                Text("Using: \(currentConfig.name)")
                    .disabled(true)
                Divider()
            }
            
            // Screenshot section - UNCHANGED
            Text("Screenshots")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Capture Region") {
                print("MenuBarView: Capture Region button clicked")
                captureHandler.captureRegion()
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            .disabled(configManager.selectedConfig == nil)
            
            Button("Capture Window") {
                print("MenuBarView: Capture Window button clicked")
                captureHandler.captureWindow()
            }
            .keyboardShortcut("2", modifiers: [.command, .shift])
            .disabled(configManager.selectedConfig == nil)
            
            Button("Capture Full Screen") {
                print("MenuBarView: Capture Full Screen button clicked")
                captureHandler.captureFullScreen()
            }
            .keyboardShortcut("3", modifiers: [.command, .shift])
            .disabled(configManager.selectedConfig == nil)
            
            Divider()
            
            // Single screen recording button
            Text("Screen Recording")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Screen Recording") {
                print("MenuBarView: Screen Recording button clicked")
                videoCaptureHandler.showCaptureOverlay()
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])
            .disabled(configManager.selectedConfig == nil)
            
            Divider()
            
            Menu("Upload Target") {
                ForEach(configManager.configurations) { config in
                    Button(action: {
                        print("MenuBarView: Selected config: \(config.name)")
                        configManager.selectedConfig = config
                    }) {
                        HStack {
                            Text(config.name)
                            Spacer()
                            if config.id == configManager.selectedConfig?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("Quit SnapShareUp") {
                print("MenuBarView: Quit button clicked")
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .onAppear {
            print("MenuBarView: View appeared")
            print("MenuBarView: CaptureHandler passed directly: \(captureHandler)")
            print("MenuBarView: VideoCaptureHandler passed directly: \(videoCaptureHandler)")
            print("MenuBarView: Selected config: \(configManager.selectedConfig?.name ?? "none")")
        }
    }
}
extension View {
    func checkmark(_ showCheckmark: Bool) -> some View {
        modifier(CheckmarkModifier(showCheckmark: showCheckmark))
    }
}

struct CheckmarkModifier: ViewModifier {
    let showCheckmark: Bool
    
    func body(content: Content) -> some View {
        HStack {
            content
            if showCheckmark {
                Image(systemName: "checkmark")
            }
        }
    }
}
