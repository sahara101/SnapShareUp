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
            
            // Show popup with options
            showActionPopup(for: image)
            
            // Clean up temp file after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? FileManager.default.removeItem(atPath: tempFilePath)
            }
        } else {
            isUploading = false
            showNotification(title: "Capture Failed", body: "No screenshot was taken")
        }
    }
    
    private func showActionPopup(for image: NSImage) {
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
}
