import Foundation
import AppKit
import AVFoundation
import SwiftUI
import ScreenCaptureKit

// Content Sharing Picker Manager Class
class ContentSharingPickerManager: NSObject, SCContentSharingPickerObserver {
    static let shared = ContentSharingPickerManager()
    private let picker = SCContentSharingPicker.shared
    
    private var contentSelectedCallback: (SCContentFilter, SCStream?) -> Void = { _, _ in }
    private var contentSelectionFailedCallback: (Error) -> Void = { _ in }
    private var contentSelectionCancelledCallback: (SCStream?) -> Void = { _ in }
    
    func setContentSelectedCallback(_ callback: @escaping @Sendable (SCContentFilter, SCStream?) -> Void) async {
        contentSelectedCallback = callback
    }
    
    func setContentSelectionFailedCallback(_ callback: @escaping @Sendable (Error) -> Void) async {
        contentSelectionFailedCallback = callback
    }
    
    func setContentSelectionCancelledCallback(_ callback: @escaping @Sendable (SCStream?) -> Void) async {
        contentSelectionCancelledCallback = callback
    }
    
    func setupPicker(stream: SCStream) {
        picker.add(self)
        picker.isActive = true
        
        var pickerConfig = SCContentSharingPickerConfiguration()
        pickerConfig.allowsChangingSelectedContent = true
        
        picker.setConfiguration(pickerConfig, for: stream)
    }
    
    func showPicker() {
        picker.present()
    }
    
    func deactivatePicker() {
        picker.isActive = false
        picker.remove(self)
    }
    
    // MARK: SCContentSharingPickerObserver methods
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async {
            self.contentSelectedCallback(filter, stream)
        }
    }
    
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async {
            self.contentSelectionCancelledCallback(stream)
        }
    }
    
    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async {
            self.contentSelectionFailedCallback(error)
        }
    }
}

// CaptureEngineOutput Class
class CaptureEngineOutput: NSObject, SCStreamOutput, SCStreamDelegate, SCRecordingOutputDelegate {
    private var continuation: AsyncThrowingStream<Void, Error>.Continuation
    
    init(continuation: AsyncThrowingStream<Void, Error>.Continuation) {
        self.continuation = continuation
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        // We don't need to process the sample buffers in this implementation
    }
    
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && nsError.code == -3817 {
            // This appears to be the normal behavior when stopping a stream
            print("Stream stopped by user - error code -3817")
            
            // Post a notification for successful recording completion
            NotificationCenter.default.post(
                name: Notification.Name("ScreenRecordingCompleted"),
                object: nil
            )
            
            // Just finish without throwing an error
            continuation.finish()
        } else {
            // Only treat other errors as actual errors
            continuation.finish(throwing: error)
        }
    }
    
    func recordingOutput(_ output: SCRecordingOutput, didFinishRecordingTo url: URL, error: Error?) {
        if let error = error {
            continuation.finish(throwing: error)
        }
    }
}

// CaptureEngine Class
class CaptureEngine: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var output: CaptureEngineOutput?
    private var recordingOutput: SCRecordingOutput?
    private var fileURL: URL?
    
    func startCapture(configuration: SCStreamConfiguration, filter: SCContentFilter, fileURL: URL) -> AsyncThrowingStream<Void, Error> {
        self.fileURL = fileURL
        
        return AsyncThrowingStream<Void, Error> { continuation in
            do {
                // Create the output handler
                let output = CaptureEngineOutput(continuation: continuation)
                self.output = output
                
                // Create the stream
                stream = SCStream(filter: filter, configuration: configuration, delegate: output)
                
                // Add video output
                try stream?.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.snapshareup.VideoSampleBufferQueue"))
                
                // Setup recording output
                let recordingConfiguration = SCRecordingOutputConfiguration()
                recordingConfiguration.outputURL = fileURL
                recordingConfiguration.outputFileType = .mp4
                
                recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: output)
                try stream?.addRecordingOutput(recordingOutput!)
                
                // Start the capture
                stream?.startCapture()
                
                // Provide a single value to keep the stream alive
                continuation.yield(())
                
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
    
    func stopCapture() async -> (@Sendable @escaping (Result<URL, Error>) -> Void) -> Void {
        return { [weak self] (completion: @escaping (Result<URL, Error>) -> Void) in
            guard let self = self, let url = self.fileURL else {
                completion(.failure(NSError(domain: "com.snapshareup", code: 1, userInfo: [NSLocalizedDescriptionKey: "No file URL"])))
                return
            }
            
            // Stop the stream with a completion handler
            self.stream?.stopCapture { (error: Error?) in
                // Handle the specific error code -3817 as a success case
                // This error occurs when the user manually stops the recording
                if let nsError = error as? NSError,
                   nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" &&
                   nsError.code == -3817 {
                    
                    print("User stopped the stream - treating as successful completion")
                    
                    DispatchQueue.main.async {
                        // Deactivate picker first
                        ContentSharingPickerManager.shared.deactivatePicker()
                        
                        // Clear references
                        self.stream = nil
                        self.output = nil
                        self.recordingOutput = nil
                        
                        // Check if file exists
                        if FileManager.default.fileExists(atPath: url.path) {
                            // Complete with success
                            completion(.success(url))
                        } else {
                            let fileError = NSError(domain: "com.snapshareup", code: 2,
                                                  userInfo: [NSLocalizedDescriptionKey: "Recording file not found"])
                            completion(.failure(fileError))
                        }
                    }
                } else if let error = error {
                    // Handle other errors
                    print("Error stopping capture: \(error)")
                    completion(.failure(error))
                } else {
                    // Normal success path
                    DispatchQueue.main.async {
                        ContentSharingPickerManager.shared.deactivatePicker()
                        self.stream = nil
                        self.output = nil
                        self.recordingOutput = nil
                        completion(.success(url))
                    }
                }
            }
        }
    }
}

// Main ScreenRecorder Class
class ScreenRecorder: NSObject, @unchecked Sendable, ObservableObject {
    @Published var isRecording = false
    
    // Callback for when recording is finished
    var onRecordingComplete: ((URL) -> Void)?
    
    private var captureEngine = CaptureEngine()
    var fileURL: URL?
    
    override init() {
        super.init()
        print("ScreenRecorder: Initialized")
    }
    
    func prepareRecording() {
        print("ScreenRecorder: Preparing for recording")
        
        // Check permissions
        Task {
            if await canRecord() {
                print("ScreenRecorder: Permission granted")
            } else {
                print("ScreenRecorder: Permission denied")
                await MainActor.run {
                    self.showPermissionAlert()
                }
            }
        }
    }
    
    private func canRecord() async -> Bool {
        do {
            // This will prompt for permissions if needed
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            print("ScreenRecorder: Permission error: \(error)")
            return false
        }
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Please allow SnapShareUp to record your screen in System Settings > Privacy & Security > Screen Recording, then restart the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // Record the entire screen
    func recordFullScreen() {
        print("ScreenRecorder: Starting full screen recording")
        startRecording()
    }
    
    // Record a selected region
    func recordRegion() {
        print("ScreenRecorder: Starting region recording")
        startRecording()
    }
    
    // Record a window
    func recordWindow() {
        print("ScreenRecorder: Starting window recording")
        startRecording()
    }
    
    private func startRecording() {
        // Create a temporary file path for the recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording_\(Int(Date().timeIntervalSince1970)).mp4"
        let fileURL = tempDir.appendingPathComponent(fileName)
        self.fileURL = fileURL
        
        print("ScreenRecorder: Will save recording to \(fileURL.path)")
        
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // Create a local copy of fileURL to avoid capturing self
        let localFileURL = fileURL
        
        Task {
            if await canRecord() {
                await startCaptureWithPicker(fileURL: localFileURL)
            } else {
                print("ScreenRecorder: Permission denied")
                await MainActor.run {
                    self.showPermissionAlert()
                    NotificationCenter.default.post(name: Notification.Name("ScreenRecordingCanceled"), object: nil)
                }
            }
        }
    }
    
    private func startCaptureWithPicker(fileURL: URL) async {
        let pickerManager = ContentSharingPickerManager.shared
        
        // Create a weak reference to self to avoid sendable issues
        await pickerManager.setContentSelectedCallback { [weak self] (filter: SCContentFilter, stream: SCStream?) in
            guard let self = self else { return }
            
            Task {
                await self.startCaptureWithFilter(filter, fileURL: fileURL)
            }
        }
        
        await pickerManager.setContentSelectionCancelledCallback { [weak self] (stream: SCStream?) in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.isRecording = false
                NotificationCenter.default.post(name: Notification.Name("ScreenRecordingCanceled"), object: nil)
            }
        }
        
        await pickerManager.setContentSelectionFailedCallback { [weak self] (error: Error) in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.isRecording = false
                NotificationCenter.default.post(name: Notification.Name("ScreenRecordingCanceled"), object: nil)
            }
        }
        
        // Create a dummy configuration and filter for the picker
        let config = SCStreamConfiguration()
        let dummyFilter = SCContentFilter()
        let stream = SCStream(filter: dummyFilter, configuration: config, delegate: nil)
        
        // Show the content picker
        pickerManager.setupPicker(stream: stream)
        pickerManager.showPicker()
    }
    
    private func startCaptureWithFilter(_ filter: SCContentFilter, fileURL: URL) async {
        let config = SCStreamConfiguration()
        config.width = 3840
        config.height = 2160
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.capturesAudio = false
        
        await MainActor.run {
            self.isRecording = true
        }
        
        do {
            // Start the capture
            for try await _ in captureEngine.startCapture(configuration: config, filter: filter, fileURL: fileURL) {
                // Just iterate to keep the stream alive
            }
        } catch {
            print("ScreenRecorder ERROR: \(error)")
            await MainActor.run {
                self.isRecording = false
                NotificationCenter.default.post(name: Notification.Name("ScreenRecordingCanceled"), object: nil)
            }
        }
    }
    
    func stopRecording() {
        print("ScreenRecorder: Stopping recording")
        
        // Store the current fileURL to use in the completion handler
        let currentFileURL = fileURL
        
        Task {
            let stopClosure = await captureEngine.stopCapture()
            
            stopClosure { [weak self] result in
                guard let self = self else { return }
                
                Task { @MainActor in
                    self.isRecording = false
                    
                    // Even if we get an error, check if the file exists
                    if let url = currentFileURL, FileManager.default.fileExists(atPath: url.path) {
                        print("ScreenRecorder: Recording file exists after stop: \(url.path)")
                        self.onRecordingComplete?(url)
                    } else {
                        print("ScreenRecorder: No valid recording file found")
                        NotificationCenter.default.post(name: Notification.Name("ScreenRecordingCanceled"), object: nil)
                    }
                }
            }
        }
    }
    
    func generateThumbnail(from videoURL: URL) -> NSImage? {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Use a semaphore to make this method synchronous but still use the modern API
        let semaphore = DispatchSemaphore(value: 0)
        var thumbnail: NSImage?
        
        imageGenerator.generateCGImageAsynchronously(for: CMTime(seconds: 0, preferredTimescale: 60)) { cgImage, time, error in
            defer { semaphore.signal() } // Always signal the semaphore
            
            if let error = error {
                print("Error generating thumbnail: \(error)")
                return
            }
            
            if let cgImage = cgImage {
                thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
        
        // Wait with a timeout to avoid blocking indefinitely
        let timeout = DispatchTime.now() + 2.0
        let result = semaphore.wait(timeout: timeout)
        
        if result == .timedOut {
            print("Thumbnail generation timed out")
        }
        
        return thumbnail
    }
}
