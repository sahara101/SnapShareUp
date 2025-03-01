import SwiftUI
import AppKit

class EditorWindowController: NSWindowController, NSToolbarDelegate {
    private var editorView: ImageEditorView!
    private var onSave: (NSImage) -> Void
    
    init(image: NSImage, onSave: @escaping (NSImage) -> Void) {
        self.onSave = onSave
        
        // Create window with reasonable default size
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        window.title = "Edit Screenshot"
        window.minSize = NSSize(width: 400, height: 300)
        
        // Set up the editor view
        self.editorView = ImageEditorView(image: image)
        window.contentView = self.editorView
        
        // Center window on screen
        window.center()
        
        setupToolbar()
        setupKeyboardShortcuts()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconAndLabel
        window?.toolbar = toolbar
    }
    
    private func setupKeyboardShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "a":
                    self.editorView.currentTool = .arrow
                    return nil
                case "t":
                    self.editorView.currentTool = .text
                    return nil
                case "h":
                    self.editorView.currentTool = .highlight
                    return nil
                case "b":
                    self.editorView.currentTool = .blur
                    return nil
                case "s":
                    self.saveImage(nil)
                    return nil
                case "w":
                    self.close()
                    return nil
                case "z":
                    if event.modifierFlags.contains(.shift) {
                        self.editorView.redo()
                    } else {
                        self.editorView.undo()
                    }
                    return nil
                default:
                    break
                }
            }
            
            return event
        }
    }
    
    @objc private func selectTool(_ sender: NSSegmentedControl) {
        let tools: [EditTool] = [.arrow, .text, .highlight, .blur]
        if sender.selectedSegment >= 0 && sender.selectedSegment < tools.count {
            editorView.currentTool = tools[sender.selectedSegment]
        }
    }
    
    @objc private func undoAction(_ sender: Any?) {
        editorView.undo()
    }
    
    @objc private func saveImage(_ sender: Any?) {
        if let editedImage = editorView.getEditedImage() {
            onSave(editedImage)
            close()
        }
    }
    
    @objc private func cancelEditing(_ sender: Any?) {
        close()
    }
    
    // MARK: - NSToolbarDelegate
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            NSToolbarItem.Identifier("tools"),
            NSToolbarItem.Identifier("undo"),
            .flexibleSpace,
            NSToolbarItem.Identifier("save"),
            NSToolbarItem.Identifier("cancel")
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier.rawValue {
        case "tools":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Tools"
            
            let segmentedControl = NSSegmentedControl(images: [
                NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Arrow")!,
                NSImage(systemSymbolName: "textformat", accessibilityDescription: "Text")!,
                NSImage(systemSymbolName: "highlighter", accessibilityDescription: "Highlight")!,
                NSImage(systemSymbolName: "app.connected.to.app.below.fill", accessibilityDescription: "Blur")!
            ], trackingMode: .selectOne, target: self, action: #selector(selectTool(_:)))
            
            segmentedControl.setToolTip("Arrow (⌘A)", forSegment: 0)
            segmentedControl.setToolTip("Text (⌘T)", forSegment: 1)
            segmentedControl.setToolTip("Highlight (⌘H)", forSegment: 2)
            segmentedControl.setToolTip("Blur (⌘B)", forSegment: 3)
            
            item.view = segmentedControl
            return item
            
        case "undo":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Undo"
            item.toolTip = "Undo last action (⌘Z)"
            item.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")
            item.target = self
            item.action = #selector(undoAction(_:))
            return item
            
        case "save":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Save"
            item.toolTip = "Save changes (⌘S)"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
            item.target = self
            item.action = #selector(saveImage(_:))
            return item
            
        case "cancel":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Cancel"
            item.toolTip = "Cancel editing (⌘W)"
            item.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel")
            item.target = self
            item.action = #selector(cancelEditing(_:))
            return item
            
        default:
            return nil
        }
    }
}
