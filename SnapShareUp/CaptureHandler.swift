import SwiftUI
import CoreGraphics
import UserNotifications
import AppKit

class CaptureHandler: ObservableObject {
    weak var configManager: ConfigurationManager?
    @Published var isUploading = false
    private var popupController: ActionPopupWindowController?
    private var editorController: EditorWindowController?
    private var currentImageData: Data?
    private var loadingWindowController: LoadingWindowController?
    
    // Track Apple Frames processing state
    private var appleFramesProcessing = false
    private var appleFramesCheckTimer: Timer?
    
    init(configManager: ConfigurationManager) {
        self.configManager = configManager
    }
    
    func captureRegion() {
        capture(withArguments: ["-i"])
    }
    
    func captureWindow() {
        capture(withArguments: ["-iW", "-o"])
    }
    
    func captureFullScreen() {
        capture(withArguments: [])
    }
    
    private func capture(withArguments arguments: [String]) {
        guard configManager?.selectedConfig != nil else { return }
        
        isUploading = true
        
        // Create a temporary file path
        let tempFilePath = NSTemporaryDirectory() + "screenshot.png"
        
        // Add the file path but NOT -c (no immediate copy to clipboard)
        var fullArguments = arguments
        fullArguments.append(tempFilePath)
        
        let task = Process()
        task.launchPath = "/usr/sbin/screencapture"
        task.arguments = fullArguments
        task.launch()
        task.waitUntilExit()
        
        if let fileData = try? Data(contentsOf: URL(fileURLWithPath: tempFilePath)),
           let image = NSImage(data: fileData) {
            
            // Store the file data
            self.currentImageData = fileData
            
            // Check if Apple Frames should be used AND if this is a full screen capture
            if let configManager = configManager,
               configManager.useAppleFrames &&
               arguments.isEmpty {  // Empty arguments means full screen capture
                processWithAppleFrames(image: image, tempFilePath: tempFilePath)
            } else {
                // Original flow for non-full screen captures or when Apple Frames is disabled
                showActionPopup(for: image)
            }
            
            // Clean up temp file after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? FileManager.default.removeItem(atPath: tempFilePath)
            }
        } else {
            isUploading = false
            print("Capture Failed: No screenshot was taken")
            showNotification(title: "Capture Failed", body: "No screenshot was taken")
        }
    }
    
    private func processWithAppleFrames(image: NSImage, tempFilePath: String) {
        // Show loading indicator
        DispatchQueue.main.async {
            self.loadingWindowController = LoadingWindowController(message: "Adding device frame to screenshot...")
            self.loadingWindowController?.showWindow(nil)
        }
        
        // Save original clipboard content
        let previousClipboard = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage
        
        // Flag that we're processing
        appleFramesProcessing = true
        
        // Put the screenshot on clipboard first
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        
        // Create a small helper shortcut file that uses the API properly
        let commandFile = NSTemporaryDirectory() + "apple_frames_command.txt"
        do {
            try "clipboard&copy".write(to: URL(fileURLWithPath: commandFile), atomically: true, encoding: .utf8)
            
            // Now run the Apple Frames shortcut with this file as input
            let task = Process()
            task.launchPath = "/usr/bin/shortcuts"
            task.arguments = ["run", "Apple Frames", "--input-path", commandFile]
            try task.run()
            
            // Start monitoring for the result
            startFramesCompletionCheck(originalImage: image, previousClipboard: previousClipboard)
        } catch {
            // If command execution fails, close the loading window and show the original image
            self.appleFramesProcessing = false
            DispatchQueue.main.async {
                self.loadingWindowController?.close()
                self.loadingWindowController = nil
            }
            print("Failed to run Apple Frames shortcut: \(error)")
            showNotification(title: "Apple Frames Error", body: "Could not run Apple Frames shortcut")
            showActionPopup(for: image)
        }
    }
    
    private func startFramesCompletionCheck(originalImage: NSImage, previousClipboard: NSImage?) {
        let startTime = Date()
        let timeout: TimeInterval = 20 // 20 second timeout
        
        // Cancel any existing timer
        appleFramesCheckTimer?.invalidate()
        
        // Start a timer to check for clipboard changes
        appleFramesCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            // Update loading message occasionally to show progress
            if Date().timeIntervalSince(startTime) > 5 {
                DispatchQueue.main.async {
                    self.loadingWindowController?.updateMessage("Still processing... Please wait.")
                }
            }
            
            // Check if timeout has been reached
            if Date().timeIntervalSince(startTime) > timeout {
                self.appleFramesProcessing = false
                timer.invalidate()
                DispatchQueue.main.async {
                    self.loadingWindowController?.close()
                    self.loadingWindowController = nil
                }
                self.showNotification(title: "Apple Frames Timeout", body: "Processing took too long, using original image")
                self.showActionPopup(for: originalImage)
                return
            }
            
            // Check for a new image on the clipboard that's different from original
            if let clipboardImage = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
                // Compare dimensions/size to determine if it's a new image
                // We're looking for an image different from both the original and previous clipboard
                let isDifferentFromOriginal = clipboardImage.size != originalImage.size
                let isDifferentFromPrevious = previousClipboard == nil || clipboardImage.size != previousClipboard?.size
                
                if isDifferentFromOriginal && isDifferentFromPrevious {
                    timer.invalidate()
                    self.appleFramesProcessing = false
                    
                    // Close the loading window
                    DispatchQueue.main.async {
                        self.loadingWindowController?.close()
                        self.loadingWindowController = nil
                    }
                    
                    // Get the PNG data for possible upload
                    if let tiffData = clipboardImage.tiffRepresentation,
                       let bitmapImage = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                        self.currentImageData = pngData
                    }
                    
                    // Bring our app to the front again
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    
                    // Show the action popup with the framed image
                    self.showActionPopup(for: clipboardImage)
                }
            }
        }
    }
    
    private func showActionPopup(for image: NSImage) {
        // Cancel any ongoing Apple Frames processing
        if appleFramesProcessing {
            appleFramesCheckTimer?.invalidate()
            appleFramesProcessing = false
        }
        
        popupController = ActionPopupWindowController(
            screenshot: image,
            onUpload: { [weak self] in
                if let config = self?.configManager?.selectedConfig,
                   let imageData = self?.currentImageData {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                    self?.uploadImage(imageData: imageData, config: config)
                }
            },
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                self?.showNotification(title: "Screenshot Copied", body: "Image copied to clipboard")
                self?.isUploading = false
            },
            onEdit: { [weak self] tool in
                self?.showEditor(for: image)
            },
            onDismiss: { [weak self] in
                self?.isUploading = false
            }
        )
        
        DispatchQueue.main.async {
            self.popupController?.showWindow(nil)
        }
    }
    
    private func showEditor(for image: NSImage) {
        editorController = EditorWindowController(
            image: image,
            onSave: { [weak self] editedImage in
                // Get PNG data for possible upload
                if let tiffData = editedImage.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    self?.currentImageData = pngData
                    // Show the action popup again with edited image
                    self?.showActionPopup(for: editedImage)
                }
            }
        )
        editorController?.showWindow(nil)
    }
    
    private func uploadImage(imageData: Data, config: UploadConfig) {
        guard let url = URL(string: config.requestURL) else {
            isUploading = false
            print("Invalid URL: \(config.requestURL)")
            showNotification(title: "Upload Failed", body: "Invalid upload URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Add headers
        for header in config.headers {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }
        
        // Create form data
        var formData = Data()
        
        // Add the file
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"\(config.fileFormName)\"; filename=\"screenshot.png\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        formData.append(imageData)
        formData.append("\r\n".data(using: .utf8)!)
        
        // End the form data
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = formData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isUploading = false
                
                if let error = error {
                    self?.showNotification(title: "Upload Failed", body: error.localizedDescription)
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let files = json["files"] as? [[String: Any]],
                      let firstFile = files.first,
                      let url = firstFile["url"] as? String else {
                    self?.showNotification(title: "Upload Failed", body: "Invalid server response")
                    return
                }
                
                // Copy URL to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                
                self?.showNotification(title: "Upload Complete", body: "URL copied to clipboard")
            }
        }.resume()
    }
    
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error showing notification: \(error)")
            }
        }
    }
    
    deinit {
        appleFramesCheckTimer?.invalidate()
    }
}
