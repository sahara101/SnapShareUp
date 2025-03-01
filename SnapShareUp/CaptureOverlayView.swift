import SwiftUI
import AppKit

struct CaptureOverlayView: View {
    let onRecordRegion: () -> Void
    let onRecordFullScreen: () -> Void
    let onDismiss: () -> Void
    
    // For drag behavior
    @State private var dragOffset = CGSize.zero
    @State private var position = CGPoint(x: 100, y: 100)
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Screen Recording")
                .font(.headline)
                .padding(.top, 8)
            
            Divider()
            
            Button(action: {
                onRecordRegion()
                onDismiss()
            }) {
                HStack {
                    Image(systemName: "rectangle.dashed")
                        .font(.title2)
                    Text("Record Selected Region")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CaptureButtonStyle())
            
            Button(action: {
                onRecordFullScreen()
                onDismiss()
            }) {
                HStack {
                    Image(systemName: "rectangle")
                        .font(.title2)
                    Text("Record Entire Screen")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(CaptureButtonStyle())
            
            Divider()
            
            Button(action: {
                onDismiss()
            }) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding()
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .overlay(
            // Drag handle at the top
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .offset(x: dragOffset.width, y: dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    self.dragOffset = value.translation
                }
                .onEnded { value in
                    self.position.x += value.translation.width
                    self.position.y += value.translation.height
                    self.dragOffset = .zero
                }
        )
    }
}

struct CaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
    }
}

class CaptureOverlayWindowController: NSWindowController {
    init(
        onRecordRegion: @escaping () -> Void,
        onRecordFullScreen: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // Create a window for the overlay
        let overlayWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.hasShadow = false
        overlayWindow.level = .floating
        overlayWindow.ignoresMouseEvents = false
        
        // Position the window in the center of the screen
        if let screenFrame = NSScreen.main?.visibleFrame {
            let x = screenFrame.midX - 130 // Half the width
            let y = screenFrame.midY - 90 // Half the height
            overlayWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        super.init(window: overlayWindow)
        
        // Set the content view with the SwiftUI overlay
        let overlayView = CaptureOverlayView(
            onRecordRegion: onRecordRegion,
            onRecordFullScreen: onRecordFullScreen,
            onDismiss: {
                self.close()
                onDismiss()
            }
        )
        
        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        overlayWindow.contentView = hostingView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
