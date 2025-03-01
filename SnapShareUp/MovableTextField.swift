import AppKit

class MovableTextField: NSTextField {
    private var isDragging = false
    private var lastLocation: NSPoint?
    
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        lastLocation = event.locationInWindow
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isDragging {
            guard let lastLocation = lastLocation else { return }
            let currentLocation = event.locationInWindow
            let delta = NSPoint(
                x: currentLocation.x - lastLocation.x,
                y: currentLocation.y - lastLocation.y
            )
            
            let newOrigin = NSPoint(
                x: frame.origin.x + delta.x,
                y: frame.origin.y + delta.y
            )
            
            self.frame.origin = newOrigin
            self.lastLocation = currentLocation
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        lastLocation = nil
        super.mouseUp(with: event)
        
        if !isDragging {
            self.becomeFirstResponder()
        }
    }
}
