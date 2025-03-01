import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var configManager: ConfigurationManager
    @State private var showingNewConfig = false
    @State private var selectedConfig: UploadConfig?
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedConfig) {
                Section(header: Text("General Settings")) {
                    Toggle("Launch at Login", isOn: $configManager.launchAtLogin)
                    
                    // Add Apple Frames integration toggle
                    Toggle("Use Apple Frames", isOn: $configManager.useAppleFrames)
                        .help("Automatically apply device frames to screenshots")
                }
                
                Section(header: Text("Upload Configurations")) {
                    ForEach(configManager.configurations) { config in
                        NavigationLink(value: config) {
                            HStack {
                                Text(config.name)
                                if config.isDefault {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    HStack {
                        Button(action: { showingNewConfig = true }) {
                            Image(systemName: "plus")
                        }
                        Button(action: { configManager.importConfiguration() }) {
                            Image(systemName: "doc.badge.arrow.up")
                        }
                    }
                }
            }
        } detail: {
            if let config = selectedConfig {
                ConfigDetailView(config: config)
                    .id(config.id) // Force view refresh when config changes
            } else {
                Text("Select a configuration")
                    .foregroundColor(.secondary)
            }
        }
        .navigationDestination(for: UploadConfig.self) { config in
            ConfigDetailView(config: config)
        }
        .sheet(isPresented: $showingNewConfig) {
            NavigationStack {
                ConfigDetailView(config: nil)
            }
        }
    }
}

struct ConfigDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configManager: ConfigurationManager
    @State private var name: String = ""
    @State private var requestURL: String = ""
    @State private var fileFormName: String = ""
    @State private var responseURL: String = ""
    @State private var headers: [HeaderConfig] = []
    @State private var isDefault: Bool = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    let config: UploadConfig?
    
    init(config: UploadConfig?) {
        self.config = config
        if let config = config {
            _name = State(initialValue: config.name)
            _requestURL = State(initialValue: config.requestURL)
            _fileFormName = State(initialValue: config.fileFormName)
            _responseURL = State(initialValue: config.responseURL)
            _headers = State(initialValue: config.headers)
            _isDefault = State(initialValue: config.isDefault)
        }
    }
    
    var body: some View {
            Form {
                Section(header: Text("Basic Configuration")) {
                    TextField("Name", text: $name)
                    TextField("Request URL", text: $requestURL)
                    TextField("File Form Name", text: $fileFormName)
                    TextField("Response URL", text: $responseURL)
                    Toggle("Set as Default", isOn: $isDefault)
                }
                
                Section(header: Text("Headers")) {
                    ForEach($headers) { $header in
                        HStack {
                            TextField("Key", text: $header.key)
                            TextField("Value", text: $header.value)
                            Button(action: {
                                if let index = headers.firstIndex(where: { $0.id == header.id }) {
                                    headers.remove(at: index)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    Button("Add Header") {
                        headers.append(HeaderConfig())
                    }
                }
                
                Section {
                    HStack {
                        Button("Save") {
                            saveConfiguration()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        if config != nil {
                            Button("Export") {
                                configManager.exportConfiguration(createConfig())
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if config != nil {
                            Button("Delete", role: .destructive) {
                                if let config = config {
                                    configManager.deleteConfiguration(config)
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle(config == nil ? "New Configuration" : "Edit Configuration")
            .alert("Validation Error", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    
    private func createConfig() -> UploadConfig {
        UploadConfig(
            id: config?.id ?? UUID(),
            name: name,
            requestURL: requestURL,
            fileFormName: fileFormName,
            responseURL: responseURL,
            headers: headers,
            isDefault: isDefault
        )
    }
    
    private func saveConfiguration() {
        let newConfig = createConfig()
        
        if config == nil {
            configManager.addConfiguration(newConfig)
        } else {
            configManager.updateConfiguration(newConfig)
        }
        
        dismiss()
    }
}
