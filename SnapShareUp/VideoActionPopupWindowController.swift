import SwiftUI
import AppKit
import AVFoundation

class VideoActionPopupWindowController: NSWindowController {
    private var thumbnail: NSImage
    private var videoURL: URL
    private var onSave: () -> Void
    private var onUpload: () -> Void
    private var onCopy: () -> Void
    private var onDismiss: () -> Void
    private var resetUploadingState: () -> Void
    private var cleanupTempFile: () -> Void
    
    init(
        thumbnail: NSImage,
        videoURL: URL,
        onSave: @escaping () -> Void,
        onUpload: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        resetUploadingState: @escaping () -> Void,
        cleanupTempFile: @escaping () -> Void
    ) {
        self.thumbnail = thumbnail
        self.videoURL = videoURL
        self.onSave = onSave
        self.onUpload = onUpload
        self.onCopy = onCopy
        self.onDismiss = onDismiss
        self.resetUploadingState = resetUploadingState
        self.cleanupTempFile = cleanupTempFile
        
        // Original window size
        let contentRect = NSRect(x: 0, y: 0, width: 800, height: 600)
        let styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable]
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.isReleasedWhenClosed = false
        window.title = "Video Recording"
        window.titlebarAppearsTransparent = true
        window.level = .floating
        
        // Use macOS standard window background color
        window.backgroundColor = NSColor.windowBackgroundColor
        
        super.init(window: window)
        
        // Set the delegate to handle window closing
        window.delegate = self
        
        // Create content view
        let hostingView = NSHostingView(
            rootView: VideoActionPopupView(
                thumbnail: thumbnail,
                videoURL: videoURL,
                onSave: onSave,
                onUpload: onUpload,
                onCopy: {
                    onCopy()
                    cleanupTempFile() // Clean up after copying
                },
                onDismiss: {
                    self.close()
                    onDismiss()
                }
            )
        )
        
        // Set content view
        window.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// Add window delegate to handle window closing
extension VideoActionPopupWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Reset uploading state when window is closed with X button
        resetUploadingState()
        
        // Only clean up temp file if it's not being processed by the clipboard manager
        if !ClipboardFileManager.shared.isFileActive(videoURL.path) {
            cleanupTempFile()
        } else {
            print("VideoActionPopupWindowController: File is being used by clipboard operation, skipping cleanup")
        }
    }
}

struct VideoActionPopupView: View {
    let thumbnail: NSImage
    let videoURL: URL
    let onSave: () -> Void
    let onUpload: () -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void
    
    @State private var isPlaying = false
    @State private var isPaused = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 1.0
    
    // Use standard Mac gray color
    private let backgroundColor = Color(NSColor.windowBackgroundColor)
    
    var body: some View {
        ZStack {
            // Background color set to standard Mac window color
            backgroundColor.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Video player takes maximum space available
                ZStack {
                    if isPlaying {
                        // This is a custom video player view
                        SimpleVideoPlayerView(
                            url: videoURL,
                            isPaused: $isPaused,
                            currentTime: $currentTime,
                            duration: $duration
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            Group {
                                if isPaused {
                                    // Show play button when paused
                                    Button(action: {
                                        isPaused = false
                                    }) {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 80))
                                            .foregroundColor(.white)
                                            .shadow(radius: 2)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        )
                    } else {
                        // Thumbnail that is perfectly centered
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                            .overlay(
                                Button(action: {
                                    isPlaying = true
                                }) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 80))
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                }
                                .buttonStyle(PlainButtonStyle())
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Video seeker when playing
                if isPlaying {
                    VStack(spacing: 4) {
                        // Progress slider
                        HStack(spacing: 8) {
                            // Current time
                            Text(formatTime(currentTime))
                                .font(.system(size: 12))
                                .foregroundColor(Color(NSColor.secondaryLabelColor))
                                .frame(width: 50, alignment: .leading)
                            
                            // Seeker slider
                            Slider(
                                value: $currentTime,
                                in: 0...max(1, duration),
                                onEditingChanged: { editing in
                                    // Optional: handle seeking start/end
                                }
                            )
                            .accentColor(Color(NSColor.controlAccentColor))
                            
                            // Duration
                            Text(formatTime(duration))
                                .font(.system(size: 12))
                                .foregroundColor(Color(NSColor.secondaryLabelColor))
                                .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                }
                
                // Button bar at bottom
                HStack(spacing: 40) {
                    Button(action: {
                        onSave()
                        onDismiss()
                    }) {
                        VStack {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 32))
                            Text("Save File")
                                .font(.headline)
                        }
                        .frame(width: 150)
                        .frame(height: 80)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        onCopy()
                    }) {
                        VStack {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 32))
                            Text("Copy to Clipboard")
                                .font(.headline)
                        }
                        .frame(width: 150)
                        .frame(height: 80)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        onUpload()
                    }) {
                        VStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                            Text("Upload & Copy URL")
                                .font(.headline)
                        }
                        .frame(width: 150)
                        .frame(height: 80)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .padding(30)
        }
    }
    
    private func formatTime(_ timeInSeconds: Double) -> String {
        let minutes = Int(timeInSeconds) / 60
        let seconds = Int(timeInSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct SimpleVideoPlayerView: NSViewRepresentable {
    let url: URL
    @Binding var isPaused: Bool
    @Binding var currentTime: Double
    @Binding var duration: Double
    
    func makeNSView(context: Context) -> SimpleVideoView {
        let view = SimpleVideoView(frame: .zero)
        view.setupWithURL(url, isPaused: $isPaused, currentTime: $currentTime, duration: $duration)
        return view
    }
    
    func updateNSView(_ nsView: SimpleVideoView, context: Context) {
        nsView.updatePlayPauseState(isPaused)
        
        // Handle slider seeking
        if nsView.lastReportedTime != currentTime && !nsView.isUpdatingTime {
            nsView.seekToTime(currentTime)
        }
    }
}

class SimpleVideoView: NSView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    
    private var isPausedBinding: Binding<Bool>?
    private var currentTimeBinding: Binding<Double>?
    private var durationBinding: Binding<Double>?
    
    var lastReportedTime: Double = 0
    var isUpdatingTime: Bool = false
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
    
    func setupWithURL(
        _ url: URL,
        isPaused: Binding<Bool>,
        currentTime: Binding<Double>,
        duration: Binding<Double>
    ) {
        self.isPausedBinding = isPaused
        self.currentTimeBinding = currentTime
        self.durationBinding = duration
        
        // Create the player
        let player = AVPlayer(url: url)
        self.player = player
        
        // Create player layer
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.frame = bounds
        playerLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        layer?.addSublayer(playerLayer)
        self.playerLayer = playerLayer
        
        // Set up time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // Update current time binding
            let seconds = time.seconds
            self.isUpdatingTime = true
            self.currentTimeBinding?.wrappedValue = seconds
            self.lastReportedTime = seconds
            self.isUpdatingTime = false
            
            // Update paused state if needed
            let isActuallyPaused = player.rate == 0
            if self.isPausedBinding?.wrappedValue != isActuallyPaused {
                self.isPausedBinding?.wrappedValue = isActuallyPaused
            }
            
            // Update duration if available (fixed implementation)
            if let currentItem = player.currentItem,
               currentItem.status == .readyToPlay,
               !currentItem.duration.isIndefinite {
                self.durationBinding?.wrappedValue = currentItem.duration.seconds
            }
        }
        
        // Set up play/pause on click
        let tapGesture = NSClickGestureRecognizer(target: self, action: #selector(togglePlayPause))
        self.addGestureRecognizer(tapGesture)
        
        // Set up looping
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
        
        // Start playback
        player.play()
    }
    
    @objc private func togglePlayPause() {
        if let player = player {
            if player.rate == 0 {
                player.play()
                isPausedBinding?.wrappedValue = false
            } else {
                player.pause()
                isPausedBinding?.wrappedValue = true
            }
        }
    }
    
    @objc private func playerItemDidReachEnd() {
        player?.seek(to: .zero)
        player?.play()
        isPausedBinding?.wrappedValue = false
    }
    
    func updatePlayPauseState(_ isPaused: Bool) {
        if let player = player {
            if isPaused && player.rate != 0 {
                player.pause()
            } else if !isPaused && player.rate == 0 {
                player.play()
            }
        }
    }
    
    func seekToTime(_ time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    override func layout() {
        super.layout()
        
        // Ensure player layer fills the view and stays centered
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        playerLayer?.frame = bounds
        
        CATransaction.commit()
    }
    
    deinit {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
}
