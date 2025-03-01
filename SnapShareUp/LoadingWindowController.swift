import Cocoa

class LoadingWindowController: NSWindowController {
    private let loadingIndicator = NSProgressIndicator()
    private let loadingLabel = NSTextField()
    
    init(message: String = "Processing screenshot...") {
        // Create a window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isMovableByWindowBackground = true
        window.title = "Please Wait"
        window.backgroundColor = NSColor.windowBackgroundColor
        
        super.init(window: window)
        
        // Set up the content view
        let contentView = NSView(frame: window.contentView!.bounds)
        
        // Set up loading indicator
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .regular
        loadingIndicator.frame = NSRect(x: (contentView.bounds.width - 32) / 2, y: 60, width: 32, height: 32)
        loadingIndicator.startAnimation(nil)
        contentView.addSubview(loadingIndicator)
        
        // Set up loading text
        loadingLabel.stringValue = message
        loadingLabel.isEditable = false
        loadingLabel.isBezeled = false
        loadingLabel.drawsBackground = false
        loadingLabel.alignment = .center
        loadingLabel.frame = NSRect(x: 0, y: 20, width: contentView.bounds.width, height: 24)
        contentView.addSubview(loadingLabel)
        
        window.contentView = contentView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateMessage(_ message: String) {
        loadingLabel.stringValue = message
    }
}
