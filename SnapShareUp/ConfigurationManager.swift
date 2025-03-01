import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine
import LaunchAtLogin

@dynamicMemberLookup
class ConfigurationManager: ObservableObject {
    // MARK: - Published Properties
    @Published var configurations: [UploadConfig] = []
    @Published var selectedConfig: UploadConfig?
    @Published var isUploading = false
    
    // MARK: - UI State Properties
    var popupController: ActionPopupWindowController?
    var editorWindowController: EditorWindowController?
    var currentImageData: Data?
    var screenshot: NSImage?
    
    // MARK: - App Storage
    @AppStorage("launchAtLogin") var launchAtLogin = false {
        didSet {
            LaunchAtLogin.isEnabled = launchAtLogin
        }
    }
    @AppStorage("useAppleFrames") var useAppleFrames = false
    
    // MARK: - Constants
    private let configFileName = "snapshareup.config.json"
    
    // MARK: - Initialization
    init() {
        print("Initializing ConfigurationManager")
        loadConfigurations()
        if configurations.isEmpty {
            print("Creating default configuration")
            createDefaultConfiguration()
        }
        selectedConfig = configurations.first(where: { $0.isDefault }) ?? configurations.first
        print("Selected config: \(selectedConfig?.name ?? "none")")
        print("Number of configs: \(configurations.count)")
    }
    
    // MARK: - Configuration Management
    private func createDefaultConfiguration() {
        let defaultHeaders = [
            HeaderConfig(key: "Authorization", value: "YOUR_AUTH_TOKEN"),
            HeaderConfig(key: "x-zipline-max-views", value: ""),
            HeaderConfig(key: "x-zipline-original-name", value: "false"),
            HeaderConfig(key: "x-zipline-domain", value: "Override Domain"),
            HeaderConfig(key: "x-zipline-format", value: "empty or gfycat/name/uuid/date/random/")
        ]
        
        let defaultConfig = UploadConfig(
            id: UUID(),
            name: "Zipline Default",
            requestURL: "https://zipline.domain.com/api/upload",
            fileFormName: "file",
            responseURL: "{{files[0]}}",
            headers: defaultHeaders,
            isDefault: true
        )
        
        configurations = [defaultConfig]
        selectedConfig = defaultConfig
        saveConfigurations()
    }
    
    func loadConfigurations() {
        guard let configURL = getConfigFileURL() else {
            print("No config URL available")
            return
        }
        
        do {
            if FileManager.default.fileExists(atPath: configURL.path) {
                let data = try Data(contentsOf: configURL)
                configurations = try JSONDecoder().decode([UploadConfig].self, from: data)
                print("Loaded \(configurations.count) configurations")
            } else {
                print("Config file does not exist")
            }
        } catch {
            print("Error loading configurations: \(error)")
            configurations = []
        }
    }
    
    func saveConfigurations() {
        guard let configURL = getConfigFileURL() else { return }
        
        do {
            let data = try JSONEncoder().encode(configurations)
            try data.write(to: configURL)
            print("Saved configurations successfully")
        } catch {
            print("Error saving configurations: \(error)")
        }
    }
    
    // MARK: - Configuration CRUD
    func addConfiguration(_ config: UploadConfig) {
        configurations.append(config)
        if config.isDefault || configurations.count == 1 {
            selectedConfig = config
        }
        saveConfigurations()
        objectWillChange.send()
    }
    
    func updateConfiguration(_ config: UploadConfig) {
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations[index] = config
            if config.isDefault {
                selectedConfig = config
            }
            saveConfigurations()
            objectWillChange.send()
        }
    }
    
    func deleteConfiguration(_ config: UploadConfig) {
        configurations.removeAll { $0.id == config.id }
        if config.id == selectedConfig?.id {
            selectedConfig = configurations.first
        }
        saveConfigurations()
        objectWillChange.send()
    }
    
    // MARK: - File Operations
    func exportConfiguration(_ config: UploadConfig) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(config.name).json"
        
        if panel.runModal() == .OK,
           let url = panel.url {
            do {
                let data = try JSONEncoder().encode(config)
                try data.write(to: url)
            } catch {
                print("Error exporting configuration: \(error)")
            }
        }
    }
    
    func importConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK,
           let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                let config = try JSONDecoder().decode(UploadConfig.self, from: data)
                
                // Generate new UUID to avoid conflicts
                var importedConfig = config
                importedConfig.id = UUID()
                
                addConfiguration(importedConfig)
            } catch {
                print("Error importing configuration: \(error)")
            }
        }
    }
    
    // MARK: - Popup Management
    func showActionPopup(for image: NSImage) {
        screenshot = image
        popupController = ActionPopupWindowController(
            screenshot: image,
            onUpload: { [weak self] in
                guard let self = self else { return }
                if let config = self.selectedConfig,
                   let imageData = self.currentImageData {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                    self.uploadImage(imageData: imageData, config: config)
                }
            },
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                self?.showNotification(title: "Screenshot Copied", body: "Image copied to clipboard")
                self?.isUploading = false
            },
            onEdit: { [weak self] tool in
                self?.handleEditTool(tool)
            },
            onDismiss: { [weak self] in
                self?.isUploading = false
            }
        )
        
        DispatchQueue.main.async {
            self.popupController?.showWindow(nil)
        }
    }
    
    private func handleEditTool(_ tool: EditTool) {
        guard let screenshot = screenshot else { return }
        editorWindowController = EditorWindowController(
            image: screenshot,
            onSave: { [weak self] editedImage in
                self?.screenshot = editedImage
                self?.editorWindowController = nil
            }
        )
        editorWindowController?.showWindow(nil)
    }
    
    // MARK: - Helper Methods
    private func getConfigFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let appDirectory = appSupport.appendingPathComponent("SnapShareUp")
        
        if !fileManager.fileExists(atPath: appDirectory.path) {
            do {
                try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
                print("Created app directory at: \(appDirectory.path)")
            } catch {
                print("Error creating app directory: \(error)")
                return nil
            }
        }
        
        return appDirectory.appendingPathComponent(configFileName)
    }
    
    // MARK: - Dynamic Member Lookup
    subscript<T>(dynamicMember keyPath: WritableKeyPath<UploadConfig, T>) -> T? {
        get { selectedConfig?[keyPath: keyPath] }
        set {
            if let value = newValue, var config = selectedConfig {
                config[keyPath: keyPath] = value
                selectedConfig = config
            }
        }
    }
    
    // MARK: - Placeholder Methods (Implement these in your app)
    private func uploadImage(imageData: Data, config: UploadConfig) {
        // Implement your upload logic here
    }
    
    private func showNotification(title: String, body: String) {
        // Implement notification system
    }
}
