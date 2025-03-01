import SwiftUI
import CoreGraphics
import UserNotifications
import AppKit
import AVFoundation

class ClipboardFileManager {
    static let shared = ClipboardFileManager()
    private var activeFilePaths = Set<String>()
    private var lock = NSLock()
    
    func registerFile(_ path: String) {
        lock.lock()
        activeFilePaths.insert(path)
        lock.unlock()
        print("ClipboardFileManager: Registered file \(path)")
    }
    
    func unregisterFile(_ path: String) {
        lock.lock()
        activeFilePaths.remove(path)
        lock.unlock()
        print("ClipboardFileManager: Unregistered file \(path)")
    }
    
    func isFileActive(_ path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeFilePaths.contains(path)
    }
}

class ProgressViewModel: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var estimatedTimeRemaining: String = "Calculating..."
    let fileSize: String
    let totalBytes: Int
    
    private var startTime: Date
    private var uploadSpeed: Double = 0 // bytes per second
    
    init(fileSize: String, totalBytes: Int) {
        self.fileSize = fileSize
        self.totalBytes = totalBytes
        self.startTime = Date()
    }
    
    func updateProgress(_ value: Double) {
        // Force UI update on main thread
        DispatchQueue.main.async {
            // Only calculate speed after we have some progress
            if value > 0.01 && self.progress > 0 {
                // Calculate elapsed time since start
                let elapsedTime = Date().timeIntervalSince(self.startTime)
                
                // Calculate bytes transferred
                let bytesTransferred = Double(self.totalBytes) * value
                
                if elapsedTime > 0 {
                    // Calculate current upload speed (bytes/second)
                    // Use weighted average to smooth fluctuations (70% new, 30% old)
                    let instantSpeed = bytesTransferred / elapsedTime
                    
                    if self.uploadSpeed == 0 {
                        self.uploadSpeed = instantSpeed
                    } else {
                        self.uploadSpeed = (instantSpeed * 0.7) + (self.uploadSpeed * 0.3)
                    }
                    
                    // Calculate remaining bytes
                    let remainingBytes = Double(self.totalBytes) - bytesTransferred
                    
                    // Calculate remaining time in seconds
                    if self.uploadSpeed > 0 {
                        let remainingSeconds = Int(remainingBytes / self.uploadSpeed)
                        self.estimatedTimeRemaining = self.timeFormatted(seconds: remainingSeconds)
                    }
                }
            }
            
            self.progress = value
            print("Progress updated to \(Int(value * 100))% in view model")
        }
    }
    
    // Helper function to format time for display
    private func timeFormatted(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) seconds"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes) min \(remainingSeconds) sec"
        } else {
            let hours = seconds / 3600
            let minutes = (seconds % 3600) / 60
            return "\(hours) hr \(minutes) min"
        }
    }
}

// New floating indicator window controller
class RecordingIndicatorWindowController: NSWindowController {
    var onStopRecording: () -> Void
    
    init(onStopRecording: @escaping () -> Void) {
        self.onStopRecording = onStopRecording
        
        // Create a small, borderless window for the indicator
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = false
        
        // Position in bottom right corner
        if let screenFrame = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: screenFrame.maxX - 220,
                y: screenFrame.minY + 20
            ))
        }
        
        super.init(window: window)
        
        // Set the content view
        window.contentView = NSHostingView(
            rootView: RecordingIndicatorView(onStop: {
                self.onStopRecording()
                self.close()
            })
        )
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// SwiftUI view for the indicator
struct RecordingIndicatorView: View {
    let onStop: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .shadow(radius: 2)
            
            Text("Recording")
                .fontWeight(.medium)
            
            Spacer()
            
            Button(action: onStop) {
                Text("Stop")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
        )
        .shadow(radius: 5)
    }
}

struct UploadProgressView: View {
    @ObservedObject var viewModel: ProgressViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Uploading video (\(viewModel.fileSize))")
                    .font(.headline)
                Spacer()
                Text("\(Int(viewModel.progress * 100))%")
                    .font(.headline)
            }
            
            ProgressView(value: viewModel.progress)
                .progressViewStyle(LinearProgressViewStyle())
            
            HStack {
                Text("Remaining: \(viewModel.estimatedTimeRemaining)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if viewModel.progress < 1.0 {
                    Text("Please wait...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Upload complete!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }
}

// Main VideoCaptureHandler class with the modified approach
class VideoCaptureHandler: ObservableObject {
    weak var configManager: ConfigurationManager?
    @Published var isRecording = false
    @Published var isUploading = false
    @Published var isShowingOverlay = false
    
    private var captureOverlayController: CaptureOverlayWindowController?
    private var popupController: VideoActionPopupWindowController?
    private var screenRecorder = ScreenRecorder()
    private var recordingIndicator: RecordingIndicatorWindowController?
    private var progressObservations: [NSKeyValueObservation] = []
    
    init(configManager: ConfigurationManager) {
        print("VideoCaptureHandler: Initializing")
        self.configManager = configManager
        
        // Initialize screen recorder
        print("VideoCaptureHandler: Preparing screen recorder")
        screenRecorder.prepareRecording()
        
        // Setup callback for when recording is complete
        screenRecorder.onRecordingComplete = { [weak self] videoURL in
            print("VideoCaptureHandler: Recording complete callback received")
            self?.handleRecordingComplete(at: videoURL)
        }
        
        // Add observer for recording canceled notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRecordingCanceled),
            name: Notification.Name("ScreenRecordingCanceled"),
            object: nil
        )
        
        // Add observer for recording completed notification
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ScreenRecordingCompleted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("VideoCaptureHandler: Received ScreenRecordingCompleted notification")
            
            // Hide the recording indicator
            self?.hideRecordingIndicator()
            
            // Check for valid recordings in temp directory
            DispatchQueue.main.async {
                if let fileURL = self?.screenRecorder.fileURL,
                   FileManager.default.fileExists(atPath: fileURL.path) {
                    print("VideoCaptureHandler: Found recording file: \(fileURL.path)")
                    self?.handleRecordingComplete(at: fileURL)
                } else {
                    // Look for recordings in temp directory
                    let tempDir = FileManager.default.temporaryDirectory
                    do {
                        let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                        let recentRecordings = tempFiles.filter { file in
                            (file.lastPathComponent.hasPrefix("recording_") &&
                             (file.pathExtension == "mov" || file.pathExtension == "mp4")) &&
                            ((try? FileManager.default.attributesOfItem(atPath: file.path)[.creationDate] as? Date).flatMap {
                                Date().timeIntervalSince($0) < 5
                            } ?? false)
                        }.sorted { file1, file2 in
                            let date1 = (try? FileManager.default.attributesOfItem(atPath: file1.path)[.creationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
                            let date2 = (try? FileManager.default.attributesOfItem(atPath: file2.path)[.creationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
                            return date1 > date2
                        }
                        
                        if let mostRecentRecording = recentRecordings.first {
                            print("VideoCaptureHandler: Found recent recording: \(mostRecentRecording.path)")
                            self?.handleRecordingComplete(at: mostRecentRecording)
                        }
                    } catch {
                        print("VideoCaptureHandler: Error searching temp directory: \(error)")
                    }
                }
            }
        }
        
        print("VideoCaptureHandler: Initialization complete")
    }
    
    // Clean up observer when deallocating
    deinit {
        // Clean up progress observations
        progressObservations.forEach { $0.invalidate() }
        progressObservations.removeAll()
        
        // Clean up notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleRecordingCanceled() {
        print("VideoCaptureHandler: Recording was canceled")
        DispatchQueue.main.async {
            self.isRecording = false
            self.hideRecordingIndicator()
            self.showNotification(title: "Recording Canceled", body: "Screen recording was canceled")
        }
    }
    
    // Skip overlay and go directly to recording
    func showCaptureOverlay() {
        print("VideoCaptureHandler: Starting recording directly")
        captureVideoFullScreen()
    }
    
    func captureVideoRegion() {
        print("VideoCaptureHandler: captureVideoRegion called")
        guard configManager?.selectedConfig != nil else {
            print("VideoCaptureHandler ERROR: No configuration selected")
            return
        }
        
        isRecording = true
        showRecordingIndicator()
        screenRecorder.recordRegion()
    }
    
    func captureVideoWindow() {
        print("VideoCaptureHandler: captureVideoWindow called")
        guard configManager?.selectedConfig != nil else {
            print("VideoCaptureHandler ERROR: No configuration selected")
            return
        }
        
        isRecording = true
        showRecordingIndicator()
        screenRecorder.recordWindow()
    }
    
    func captureVideoFullScreen() {
        print("VideoCaptureHandler: captureVideoFullScreen called")
        guard configManager?.selectedConfig != nil else {
            print("VideoCaptureHandler ERROR: No configuration selected")
            return
        }
        
        isRecording = true
        showRecordingIndicator()
        screenRecorder.recordFullScreen()
    }
    
    func stopRecording() {
        print("VideoCaptureHandler: stopRecording called")
        
        // Hide the indicator
        hideRecordingIndicator()
        
        // Stop the recorder
        screenRecorder.stopRecording()
    }
    
    // Show a floating window indicator instead of a menu bar item
    private func showRecordingIndicator() {
        print("VideoCaptureHandler: Showing recording indicator")
        
        // Remove any existing indicator first
        hideRecordingIndicator()
        
        // Create a floating indicator window
        DispatchQueue.main.async {
            self.recordingIndicator = RecordingIndicatorWindowController(onStopRecording: { [weak self] in
                self?.stopRecording()
            })
            self.recordingIndicator?.showWindow(nil)
        }
        
        // Also show a notification
        showNotification(title: "Recording Started", body: "Recording in progress")
    }
    
    private func hideRecordingIndicator() {
        print("VideoCaptureHandler: Hiding recording indicator")
        
        // Close the floating indicator window
        DispatchQueue.main.async {
            self.recordingIndicator?.close()
            self.recordingIndicator = nil
        }
    }
    
    private func handleRecordingComplete(at videoURL: URL) {
        print("VideoCaptureHandler: Handling completed recording at: \(videoURL.path)")
        
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            // Make sure we're not already handling this file
            if self.isUploading {
                print("VideoCaptureHandler: Already uploading, skipping duplicate handling")
                return
            }
            
            self.isRecording = false
            self.isUploading = true
            
            // Double check if the file exists
            if FileManager.default.fileExists(atPath: videoURL.path) {
                print("VideoCaptureHandler: Video file exists")
                
                // Generate a thumbnail from the video
                print("VideoCaptureHandler: Generating thumbnail")
                var videoThumbnail: NSImage
                
                if let generatedThumbnail = self.screenRecorder.generateThumbnail(from: videoURL) {
                    videoThumbnail = generatedThumbnail
                } else if let fallbackImage = NSImage(named: "NSMovieFile") {
                    print("VideoCaptureHandler: Using system movie icon as fallback")
                    videoThumbnail = fallbackImage
                } else {
                    // Create a basic placeholder thumbnail
                    print("VideoCaptureHandler: Creating placeholder thumbnail")
                    videoThumbnail = NSImage(size: NSSize(width: 320, height: 180))
                    videoThumbnail.lockFocus()
                    NSColor.darkGray.setFill()
                    NSRect(x: 0, y: 0, width: 320, height: 180).fill()
                    NSColor.white.setStroke()
                    NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 300, height: 160), xRadius: 8, yRadius: 8).stroke()
                    "Video Recording".draw(at: NSPoint(x: 120, y: 90), withAttributes: [.foregroundColor: NSColor.white])
                    videoThumbnail.unlockFocus()
                }
                
                // Show the action popup
                print("VideoCaptureHandler: Showing video action popup")
                self.showVideoActionPopup(for: videoURL, thumbnail: videoThumbnail)
            } else {
                print("VideoCaptureHandler ERROR: Video file does not exist at path: \(videoURL.path)")
                self.isUploading = false
                self.showNotification(title: "Recording Failed", body: "Could not find the recorded video file")
            }
        }
    }
    
    // In the VideoCaptureHandler class
    private func showVideoActionPopup(for videoURL: URL, thumbnail: NSImage) {
        print("VideoCaptureHandler: Creating popup controller")
        
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            // Force bring the app to front first
            NSApplication.shared.activate(ignoringOtherApps: true)
            
            // Capture the fileURL for cleanup
            let fileURLToCleanup = videoURL
            
            // Create a non-throwing cleanup function
            let cleanup = {
                // Only delete if file exists and is not being processed for clipboard
                if FileManager.default.fileExists(atPath: fileURLToCleanup.path) &&
                   !ClipboardFileManager.shared.isFileActive(fileURLToCleanup.path) {
                    do {
                        try FileManager.default.removeItem(at: fileURLToCleanup)
                        print("VideoCaptureHandler: Cleaned up temp file at \(fileURLToCleanup.path)")
                    } catch {
                        print("VideoCaptureHandler: Failed to delete temp file: \(error)")
                    }
                } else {
                    print("VideoCaptureHandler: File is still active in clipboard manager or doesn't exist, skipping deletion")
                }
            }
            
            // Create and display the action popup
            self.popupController = VideoActionPopupWindowController(
                thumbnail: thumbnail,
                videoURL: videoURL,
                onSave: { [weak self] in
                    print("VideoCaptureHandler: Save button clicked")
                    self?.saveVideoFile(videoURL: videoURL)
                    // Note: saveVideoFile already handles cleanup
                },
                onUpload: { [weak self] in
                    print("VideoCaptureHandler: Upload button clicked")
                    if let config = self?.configManager?.selectedConfig {
                        do {
                            let videoData = try Data(contentsOf: videoURL)
                            print("VideoCaptureHandler: Video data loaded, size: \(videoData.count) bytes")
                            self?.uploadVideo(videoData: videoData, videoURL: videoURL, config: config)
                            // Note: uploadVideo now handles everything - don't dismiss or cleanup here
                        } catch {
                            print("VideoCaptureHandler ERROR: Error reading video data: \(error)")
                            self?.showNotification(title: "Upload Failed", body: "Could not read video file")
                            self?.isUploading = false
                            self?.popupController?.close()
                            cleanup() // Clean up on error
                        }
                    }
                },
                onCopy: { [weak self] in
                    print("VideoCaptureHandler: Copy button clicked")
                    
                    // Get file attributes to check size
                    if let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path),
                       let fileSize = attributes[.size] as? Int64 {
                        
                        // Show size notification
                        if fileSize > 100 * 1024 * 1024 {
                            print("VideoCaptureHandler: Large file detected (\(fileSize/1024/1024)MB)")
                            
                            // Warn user about large file
                            self?.showNotification(
                                title: "Large File",
                                body: "This video is \(fileSize/1024/1024)MB and may take a moment to process."
                            )
                        }
                        
                        // Use our new copy method with progress and file protection
                        self?.copyVideoToClipboard(videoURL: videoURL, fileSize: Int(fileSize))
                        
                        // Close the popup window
                        self?.popupController?.close()
                        
                        // NOTE: Don't call the cleanup function here
                    } else {
                        // Fallback if we can't get file size
                        self?.showNotification(title: "Copy Failed", body: "Could not determine file size")
                        self?.isUploading = false
                        self?.popupController?.close()
                        cleanup() // Only clean up if we couldn't start the copy process
                    }
                },
                onDismiss: { [weak self] in
                    print("VideoCaptureHandler: Popup dismissed")
                    self?.isUploading = false
                    // Cleanup happens through other mechanisms
                },
                resetUploadingState: { [weak self] in
                    // Reset uploading state when window is closed with X button
                    print("VideoCaptureHandler: Resetting uploading state")
                    self?.isUploading = false
                },
                cleanupTempFile: cleanup
            )
            
            // Give a small delay to ensure the app is fully active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                print("VideoCaptureHandler: Showing popup window")
                NSApplication.shared.activate(ignoringOtherApps: true)
                self.popupController?.showWindow(nil)
            }
        }
    }
    
    private func saveVideoFile(videoURL: URL) {
        print("VideoCaptureHandler: Saving video file")
        
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        
        // Use mp4 extension instead of mov
        let fileExtension = "mp4"
        savePanel.nameFieldStringValue = "Recording_\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
        
        // Use the proper UTType
        if let mp4Type = UTType(filenameExtension: fileExtension) {
            savePanel.allowedContentTypes = [mp4Type]
        } else {
            // Fallback
            savePanel.allowedContentTypes = [UTType.movie]
        }
        
        savePanel.title = "Save Video Recording"
        
        savePanel.begin { [weak self] result in
            guard let self = self else { return }
            
            if result == .OK, let targetURL = savePanel.url {
                do {
                    if FileManager.default.fileExists(atPath: targetURL.path) {
                        try FileManager.default.removeItem(at: targetURL)
                    }
                    
                    try FileManager.default.copyItem(at: videoURL, to: targetURL)
                    self.showNotification(title: "Video Saved", body: "Recording saved to \(targetURL.lastPathComponent)")
                } catch {
                    print("VideoCaptureHandler ERROR: Failed to save video: \(error)")
                    self.showNotification(title: "Save Failed", body: error.localizedDescription)
                }
            }
            
            // Clean up the original temp file
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                try? FileManager.default.removeItem(at: videoURL)
            }
        }
    }
    
    private func uploadVideo(videoData: Data, videoURL: URL, config: UploadConfig) {
        print("VideoCaptureHandler: Uploading video to: \(config.requestURL)")
        guard let url = URL(string: config.requestURL) else {
            isUploading = false
            popupController?.close() // Close popup on error
            print("VideoCaptureHandler ERROR: Invalid URL: \(config.requestURL)")
            showNotification(title: "Upload Failed", body: "Invalid upload URL")
            return
        }
        
        // Set up the upload request
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
        
        // Add the file - always use mp4 for consistency
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"\(config.fileFormName)\"; filename=\"recording.mp4\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        formData.append(videoData)
        formData.append("\r\n".data(using: .utf8)!)
        
        // End the form data
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Create a progress view controller and view model
        let (progressController, progressViewModel) = createUploadProgressWindow(fileSize: videoData.count)
        
        // Show progress during upload
        showNotification(title: "Upload Started", body: "Video is being uploaded...")
        
        print("VideoCaptureHandler: Starting upload task")
        
        // Use URLSession.shared.uploadTask for better progress tracking
        let uploadTask = URLSession.shared.uploadTask(with: request, from: formData) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Close the progress window
                progressController.close()
                
                // Close the popup - we're done with it regardless of outcome
                self.popupController?.close()
                
                // Reset upload state
                self.isUploading = false
                
                // Handle errors
                if let error = error {
                    print("VideoCaptureHandler ERROR: Upload failed: \(error)")
                    self.showNotification(title: "Upload Failed", body: error.localizedDescription)
                    return
                }
                
                print("VideoCaptureHandler: Upload response received")
                if let httpResponse = response as? HTTPURLResponse {
                    print("VideoCaptureHandler: HTTP status code: \(httpResponse.statusCode)")
                    
                    if httpResponse.statusCode >= 400 {
                        print("VideoCaptureHandler ERROR: Server returned error code \(httpResponse.statusCode)")
                        self.showNotification(title: "Upload Failed", body: "Server returned error: \(httpResponse.statusCode)")
                        return
                    }
                }
                
                guard let responseData = data,
                      let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      let files = json["files"] as? [[String: Any]],
                      let firstFile = files.first,
                      let fileUrl = firstFile["url"] as? String else {
                    print("VideoCaptureHandler ERROR: Invalid server response")
                    if let responseData = data, let responseStr = String(data: responseData, encoding: .utf8) {
                        print("VideoCaptureHandler: Response data: \(responseStr)")
                    }
                    self.showNotification(title: "Upload Failed", body: "Invalid server response")
                    return
                }
                
                print("VideoCaptureHandler: Upload successful, URL: \(fileUrl)")
                
                // Copy URL to clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fileUrl, forType: .string)
                
                self.showNotification(title: "Upload Complete", body: "URL copied to clipboard")
                
                // Now that the upload has succeeded, clean up the temporary file
                do {
                    try FileManager.default.removeItem(at: videoURL)
                    print("VideoCaptureHandler: Cleaned up temp file after successful upload")
                } catch {
                    print("VideoCaptureHandler: Failed to delete temp file: \(error)")
                }
            }
        }
        
        // Set up progress tracking using the view model
        let observation = uploadTask.progress.observe(\.fractionCompleted) { progress, _ in
            // Update progress using the view model - this will now update time remaining automatically
            progressViewModel.updateProgress(progress.fractionCompleted)
            print("Upload progress: \(Int(progress.fractionCompleted * 100))%")
        }
        
        // Store the observation to keep it alive
        progressObservations.append(observation)
        
        // Start the upload
        uploadTask.resume()
    }
    
    // Attempt to copy video to clipboard with alert fallback for large files
    private func copyVideoToClipboard(videoURL: URL, fileSize: Int) {
        print("VideoCaptureHandler: Starting clipboard copy for \(fileSizeFormatted(bytes: fileSize)) file")
        
        // Register file to prevent premature deletion
        ClipboardFileManager.shared.registerFile(videoURL.path)
        
        // Create progress view
        let (progressController, progressViewModel) = createCopyProgressWindow(fileSize: fileSize)
        
        // Show notification
        showNotification(title: "Copy Started", body: "Video is being copied to clipboard...")
        
        // Try copy in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var success = false
            
            do {
                DispatchQueue.main.async {
                    progressViewModel.updateProgress(0.1)
                }
                
                // Load file data
                let videoData = try Data(contentsOf: videoURL, options: .alwaysMapped)
                
                DispatchQueue.main.async {
                    progressViewModel.updateProgress(0.5)
                }
                
                // Setup pasteboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                
                let pasteboardItem = NSPasteboardItem()
                let fileExtension = videoURL.pathExtension.lowercased()
                let typeIdentifier = fileExtension == "mp4" ? "public.mpeg-4" :
                                    fileExtension == "mov" ? "com.apple.quicktime-movie" :
                                    "public.movie"
                
                DispatchQueue.main.async {
                    progressViewModel.updateProgress(0.8)
                }
                
                // Attempt to write to clipboard
                pasteboardItem.setData(videoData, forType: NSPasteboard.PasteboardType(typeIdentifier))
                
                if pasteboard.writeObjects([pasteboardItem]) {
                    DispatchQueue.main.async {
                        progressViewModel.updateProgress(1.0)
                        progressViewModel.estimatedTimeRemaining = "Complete!"
                    }
                    
                    Thread.sleep(forTimeInterval: 0.5)
                    success = true
                    
                    DispatchQueue.main.async {
                        self?.showNotification(title: "Video Copied", body: "Video content copied to clipboard")
                    }
                } else {
                    throw NSError(domain: "com.app.clipboard", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Failed to write to clipboard - file may be too large"
                    ])
                }
            } catch {
                print("VideoCaptureHandler ERROR: Failed to copy video data: \(error)")
                
                // Close progress window
                DispatchQueue.main.async {
                    progressController.close()
                    
                    // Show alert letting user know file is too large for clipboard
                    let alert = NSAlert()
                    alert.messageText = "File Too Large for Clipboard"
                    alert.informativeText = "This video (\(self?.fileSizeFormatted(bytes: fileSize) ?? "large file")) is too large to copy to the clipboard. Please use Save or Upload instead."
                    alert.alertStyle = .informational
                    
                    // Add buttons
                    alert.addButton(withTitle: "Save")
                    alert.addButton(withTitle: "Upload")
                    alert.addButton(withTitle: "Cancel")
                    
                    // Show the alert and handle response
                    NSApp.activate(ignoringOtherApps: true)
                    let response = alert.runModal()
                    
                    switch response {
                    case .alertFirstButtonReturn: // Save
                        self?.saveVideoFile(videoURL: videoURL)
                        
                    case .alertSecondButtonReturn: // Upload
                        if let config = self?.configManager?.selectedConfig {
                            do {
                                let videoData = try Data(contentsOf: videoURL)
                                self?.uploadVideo(videoData: videoData, videoURL: videoURL, config: config)
                            } catch {
                                print("VideoCaptureHandler ERROR: Error reading video data: \(error)")
                                self?.showNotification(title: "Upload Failed", body: "Could not read video file")
                                
                                // Don't delete the file on error
                                self?.isUploading = false
                            }
                        }
                        
                    default: // Cancel - do nothing, but don't delete the file
                        self?.isUploading = false
                        // Explicitly do NOT delete the file - user may want to try something else
                        ClipboardFileManager.shared.unregisterFile(videoURL.path)
                        return
                    }
                }
                
                return
            }
            
            // Close progress window and clean up on success
            DispatchQueue.main.async {
                progressController.close()
                
                // Only clean up the temp file if successful AND it still exists
                if success && FileManager.default.fileExists(atPath: videoURL.path) {
                    do {
                        try FileManager.default.removeItem(at: videoURL)
                        print("VideoCaptureHandler: Cleaned up temp file after successful clipboard operation")
                    } catch {
                        print("VideoCaptureHandler: Failed to delete temp file: \(error)")
                    }
                }
                
                // Always reset state
                self?.isUploading = false
                
                // Unregister the file
                ClipboardFileManager.shared.unregisterFile(videoURL.path)
            }
        }
    }
    
    private func createCopyProgressWindow(fileSize: Int) -> (NSWindowController, ProgressViewModel) {
        print("VideoCaptureHandler: Creating copy progress window for \(fileSizeFormatted(bytes: fileSize)) file")
        
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Copying Video to Clipboard"
        window.center()
        window.level = .floating // Ensure it stays on top
        
        // Create the progress view model with total bytes for speed calculation
        let viewModel = ProgressViewModel(
            fileSize: fileSizeFormatted(bytes: fileSize),
            totalBytes: fileSize
        )
        
        // Use the same progress view as for upload
        let progressView = UploadProgressView(viewModel: viewModel)
        
        // Set the content view
        window.contentView = NSHostingView(rootView: progressView)
        
        // Create a window controller
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        
        // Force the window to front
        window.orderFrontRegardless()
        
        // Return both the controller and view model so we can update the progress
        return (controller, viewModel)
    }
    
    private func createUploadProgressWindow(fileSize: Int) -> (NSWindowController, ProgressViewModel) {
        print("VideoCaptureHandler: Creating progress window for \(fileSizeFormatted(bytes: fileSize)) file")
        
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Uploading Video"
        window.center()
        window.level = .floating // Ensure it stays on top
        
        // Create the progress view model with total bytes for speed calculation
        let viewModel = ProgressViewModel(
            fileSize: fileSizeFormatted(bytes: fileSize),
            totalBytes: fileSize
        )
        
        // Create the progress view with the view model
        let progressView = UploadProgressView(viewModel: viewModel)
        
        // Set the content view
        window.contentView = NSHostingView(rootView: progressView)
        
        // Create a window controller
        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        
        // Force the window to front
        window.orderFrontRegardless()
        
        // Return both the controller and view model so we can update the progress
        return (controller, viewModel)
    }
    
    // Helper function to format file size for display
    private func fileSizeFormatted(bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // Helper function to format time for display
    private func timeFormatted(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) seconds"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes) min \(remainingSeconds) sec"
        }
    }
    
    private func showNotification(title: String, body: String) {
        print("VideoCaptureHandler: Showing notification - \(title): \(body)")
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
                print("VideoCaptureHandler ERROR: Error showing notification: \(error)")
            }
        }
    }
}
