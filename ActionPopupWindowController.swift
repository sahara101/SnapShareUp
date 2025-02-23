import SwiftUI
import AppKit

class ActionPopupWindowController: NSWindowController {
    private let onUpload: () -> Void
    private let onCopy: () -> Void
    private let onEdit: (EditTool) -> Void
    private let onDismiss: () -> Void
    
    init(screenshot: NSImage, onUpload: @escaping () -> Void, onCopy: @escaping () -> Void, onEdit: @escaping (EditTool) -> Void, onDismiss: @escaping () -> Void) {
        self.onUpload = onUpload
        self.onCopy = onCopy
        self.onEdit = onEdit
        self.onDismiss = onDismiss
        
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Screenshot Actions"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.hasShadow = true
        
        // Position near the cursor
        if let screenFrame = NSScreen.main?.frame {
            let mouseLocation = NSEvent.mouseLocation
            let panelFrame = NSRect(
                x: mouseLocation.x - 300,  // Center horizontally
                y: screenFrame.maxY - mouseLocation.y - 250,  // Adjust vertical position
                width: 600,
                height: 500
            )
            panel.setFrame(panelFrame, display: false)
        } else {
            panel.center()
        }
        
        let hostingView = NSHostingView(rootView: CaptureActionPopup(
            screenshot: screenshot,
            onUpload: {
                panel.close()
                onUpload()
            },
            onCopy: {
                panel.close()
                onCopy()
            },
            onEdit: { tool in
                panel.close()
                onEdit(tool)
            },
            onDismiss: {
                panel.close()
                onDismiss()
            }
        ))
        panel.contentView = hostingView
        
        super.init(window: panel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func close() {
        super.close()
        onDismiss()
    }
}
