import AppKit

public enum EditorAction {
    case shape(CAShapeLayer)
    case text(CATextLayer, NSRect)
    case blur(CALayer)
}
