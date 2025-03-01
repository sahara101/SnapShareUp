import SwiftUI
import AppKit
import CoreImage

class ImageEditorView: NSView {
    // MARK: - Properties
    let image: NSImage
    var currentTool: EditTool = .arrow
    
    // Views
    private var imageView: NSImageView!
    private var overlayContainer: NSView!
    private var scrollView: NSScrollView!
    
    // Drawing state
    private var shapeLayer: CALayer?
    private var drawPath: CGMutablePath?
    private var lastPoint: NSPoint?
    private var tempLayer: CALayer?
    
    // Text editing state
    private var isAddingText = false
    private var textStartPoint: NSPoint?
    
    // History
    private let editorHistory = EditorHistory()
    
    // MARK: - Initialization
    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // Create scroll view
        scrollView = NSScrollView(frame: bounds)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        addSubview(scrollView)
        
        // Create clip view
        let clipView = NSClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        
        // Setup image view
        imageView = NSImageView(frame: bounds)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        
        // Setup overlay container
        overlayContainer = NSView(frame: bounds)
        overlayContainer.wantsLayer = true
        overlayContainer.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Create container view
        let containerView = NSView(frame: bounds)
        containerView.wantsLayer = true
        containerView.addSubview(imageView)
        containerView.addSubview(overlayContainer)
        
        // Add to scroll view
        scrollView.documentView = containerView
        
        // Setup shape layer
        shapeLayer = CALayer()
        shapeLayer?.frame = bounds
        overlayContainer.layer?.addSublayer(shapeLayer!)
        
        // Enable mouse tracking
        let options: NSTrackingArea.Options = [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .enabledDuringMouseDrag]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    // MARK: - Layout
    override func layout() {
        super.layout()
        
        // Update frame to fit image proportionally
        let imageSize = image.size
        let viewSize = bounds.size
        
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height
        
        var newImageFrame = bounds
        
        if imageAspect > viewAspect {
            // Image is wider than view
            newImageFrame.size.height = newImageFrame.width / imageAspect
            newImageFrame.origin.y = (viewSize.height - newImageFrame.height) / 2
        } else {
            // Image is taller than view
            newImageFrame.size.width = newImageFrame.height * imageAspect
            newImageFrame.origin.x = (viewSize.width - newImageFrame.width) / 2
        }
        
        imageView.frame = newImageFrame
        overlayContainer.frame = newImageFrame
        shapeLayer?.frame = overlayContainer.bounds
        
        if let containerView = scrollView.documentView {
            containerView.frame = newImageFrame
        }
    }
    
    // MARK: - Mouse Events
    override func mouseDown(with event: NSEvent) {
        let windowPoint = event.locationInWindow
        let point = overlayContainer.convert(convert(windowPoint, from: nil), from: self)
        lastPoint = point
        
        if currentTool == .text {
            isAddingText = true
            textStartPoint = point
        } else {
            drawPath = CGMutablePath()
            drawPath?.move(to: point)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = lastPoint else { return }
        let windowPoint = event.locationInWindow
        let point = overlayContainer.convert(convert(windowPoint, from: nil), from: self)
        
        switch currentTool {
        case .text:
            if isAddingText, let startPoint = textStartPoint {
                overlayContainer.subviews.filter { $0 is NSTextField }.forEach { $0.removeFromSuperview() }
                
                let minX = min(startPoint.x, point.x)
                let minY = min(startPoint.y, point.y)
                let width = abs(point.x - startPoint.x)
                let height = abs(point.y - startPoint.y)
                
                let textField = MovableTextField(frame: NSRect(x: minX, y: minY, width: max(50, width), height: max(20, height)))
                textField.isEditable = false
                textField.isBordered = false
                textField.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.1)
                textField.stringValue = "Enter text"
                textField.font = .systemFont(ofSize: 14)
                overlayContainer.addSubview(textField)
            }
        case .arrow:
            drawArrow(from: start, to: point)
        case .highlight:
            if let path = drawPath {
                path.addLine(to: point)
                drawHighlight(path: path)
            }
        case .blur:
            drawBlur(from: start, to: point)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let windowPoint = event.locationInWindow
        let point = overlayContainer.convert(convert(windowPoint, from: nil), from: self)
        
        if currentTool == .text && isAddingText {
            isAddingText = false
            
            overlayContainer.subviews.filter { $0 is NSTextField }.forEach { $0.removeFromSuperview() }
            
            guard let startPoint = textStartPoint,
                  abs(point.x - startPoint.x) > 10 || abs(point.y - startPoint.y) > 10 else {
                textStartPoint = nil
                return
            }
            
            let minX = min(startPoint.x, point.x)
            let minY = min(startPoint.y, point.y)
            let width = max(50, abs(point.x - startPoint.x))
            let height = max(20, abs(point.y - startPoint.y))
            
            let textField = MovableTextField(frame: NSRect(x: minX, y: minY, width: width, height: height))
            textField.isEditable = true
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.stringValue = "Enter text"
            textField.font = .systemFont(ofSize: 14)
            overlayContainer.addSubview(textField)
            textField.delegate = self
            textField.becomeFirstResponder()
            
            textStartPoint = nil
        } else if let tempShape = tempLayer {
            switch currentTool {
            case .blur:
                // tempShape is already our blur layer, just add it to history
                editorHistory.addAction(.blur(tempShape))
                tempLayer = nil  // Clear the reference but DON'T remove from superlayer
                
            case .arrow, .highlight:
                // For arrows and highlights, create a new permanent shape layer
                if let tempShapeLayer = tempShape as? CAShapeLayer {
                    let permanent = CAShapeLayer()
                    permanent.path = tempShapeLayer.path
                    permanent.strokeColor = tempShapeLayer.strokeColor
                    permanent.fillColor = tempShapeLayer.fillColor
                    permanent.lineWidth = tempShapeLayer.lineWidth
                    permanent.lineCap = tempShapeLayer.lineCap
                    shapeLayer?.addSublayer(permanent)
                    editorHistory.addAction(.shape(permanent))
                    tempShape.removeFromSuperlayer()  // Only remove for shapes, not blur
                }
                
            case .text:
                break // Text is handled in the first branch
            }
        }
        
        // Clear all temporary states
        tempLayer = nil
        lastPoint = nil
        drawPath = nil
    }
    
    // MARK: - Drawing Functions
    private func drawArrow(from start: CGPoint, to end: CGPoint) {
        let arrow = CAShapeLayer()
        let path = CGMutablePath()
        
        // Draw arrow shaft
        path.move(to: start)
        path.addLine(to: end)
        
        // Calculate arrow head
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 20.0
        let arrowAngle: CGFloat = .pi / 8
        
        let arrowPoint1 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        
        path.move(to: end)
        path.addLine(to: arrowPoint1)
        path.move(to: end)
        path.addLine(to: arrowPoint2)
        
        arrow.path = path
        arrow.strokeColor = NSColor.systemRed.cgColor
        arrow.lineWidth = 2
        arrow.fillColor = nil
        
        tempLayer?.removeFromSuperlayer()
        tempLayer = arrow
        shapeLayer?.addSublayer(arrow)
    }
    
    private func drawHighlight(path: CGPath) {
        let highlight = CAShapeLayer()
        highlight.path = path
        highlight.strokeColor = NSColor.systemYellow.withAlphaComponent(0.5).cgColor
        highlight.lineWidth = 20
        highlight.lineCap = .round
        highlight.fillColor = nil
        
        tempLayer?.removeFromSuperlayer()
        tempLayer = highlight
        shapeLayer?.addSublayer(highlight)
    }
    
    private func drawBlur(from start: CGPoint, to end: CGPoint) {
        // Remove previous temporary layer if exists
        tempLayer?.removeFromSuperlayer()
        
        guard let cgImage = imageView.image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        let rect = NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        
        // Convert view coordinates to image coordinates
        let imageSize = imageView.image?.size ?? .zero
        let viewSize = imageView.frame.size
        let scaleX = imageSize.width / viewSize.width
        let scaleY = imageSize.height / viewSize.height
        
        let imageRect = CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        
        // Create CIImage and apply blur
        let ciImage = CIImage(cgImage: cgImage)
        let croppedImage = ciImage.cropped(to: imageRect)
        
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return }
        filter.setValue(croppedImage, forKey: kCIInputImageKey)
        filter.setValue(10.0, forKey: kCIInputRadiusKey)
        
        guard let outputImage = filter.outputImage else { return }
        
        let context = CIContext()
        guard let blurredCGImage = context.createCGImage(outputImage, from: outputImage.extent) else { return }
        
        // Create layer with blurred image
        let blurLayer = CALayer()
        blurLayer.frame = rect
        blurLayer.contents = blurredCGImage
        
        // Update temp layer
        tempLayer = blurLayer
        shapeLayer?.addSublayer(blurLayer)  // Add directly to shapeLayer instead of overlayContainer
    }
    
    // MARK: - Undo/Redo
        func undo() {
            if let action = editorHistory.undo() {
                switch action {
                case .shape(let layer):
                    layer.removeFromSuperlayer()
                case .text(let layer, _):
                    layer.removeFromSuperlayer()
                case .blur(let layer):
                    layer.removeFromSuperlayer()
                }
            }
        }
        
        func redo() {
            if let action = editorHistory.redo() {
                switch action {
                case .shape(let layer):
                    shapeLayer?.addSublayer(layer)
                case .text(let layer, _):
                    shapeLayer?.addSublayer(layer)
                case .blur(let layer):
                    shapeLayer?.addSublayer(layer)
                }
            }
        }
        
        // MARK: - Image Saving
        func getEditedImage() -> NSImage? {
            // Get the frame of the image view
            let bounds = imageView.bounds
            
            // Create a new image with the same size
            let finalImage = NSImage(size: bounds.size)
            finalImage.lockFocus()
            
            guard let context = NSGraphicsContext.current else {
                finalImage.unlockFocus()
                return nil
            }
            
            // Draw the original image
            if let originalImage = imageView.image {
                originalImage.draw(in: bounds)
            }
            
            // Convert any remaining text fields to layers
            for view in overlayContainer.subviews {
                if let textField = view as? NSTextField {
                    let textLayer = CATextLayer()
                    textLayer.string = textField.stringValue
                    textLayer.font = textField.font
                    textLayer.fontSize = textField.font?.pointSize ?? 14
                    textLayer.foregroundColor = NSColor.systemBlue.cgColor
                    textLayer.frame = textField.frame
                    textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
                    
                    shapeLayer?.addSublayer(textLayer)
                    editorHistory.addAction(.text(textLayer, textField.frame))
                    textField.removeFromSuperview()
                }
            }
            
            // Draw all the layers (arrows, highlights, text, etc.)
            shapeLayer?.render(in: context.cgContext)
            
            finalImage.unlockFocus()
            return finalImage
        }
    }

    // MARK: - NSTextFieldDelegate
    extension ImageEditorView: NSTextFieldDelegate {
        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            
            // Keep text field around until the user clicks away
            if window?.firstResponder == textField {
                return
            }
            
            let textLayer = CATextLayer()
            textLayer.string = textField.stringValue
            textLayer.font = textField.font
            textLayer.fontSize = textField.font?.pointSize ?? 14
            textLayer.foregroundColor = NSColor.systemBlue.cgColor
            textLayer.frame = textField.frame
            textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            
            shapeLayer?.addSublayer(textLayer)
            editorHistory.addAction(.text(textLayer, textField.frame))
            textField.removeFromSuperview()
        }
    }

