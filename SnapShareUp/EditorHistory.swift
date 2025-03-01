import AppKit

public class EditorHistory {
    private var undoStack: [EditorAction] = []
    private var redoStack: [EditorAction] = []
    
    public init() {}
    
    public func addAction(_ action: EditorAction) {
        undoStack.append(action)
        redoStack.removeAll()
    }
    
    public func canUndo() -> Bool {
        return !undoStack.isEmpty
    }
    
    public func canRedo() -> Bool {
        return !redoStack.isEmpty
    }
    
    public func undo() -> EditorAction? {
        guard let action = undoStack.popLast() else { return nil }
        redoStack.append(action)
        return action
    }
    
    public func redo() -> EditorAction? {
        guard let action = redoStack.popLast() else { return nil }
        undoStack.append(action)
        return action
    }
    
    public func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
