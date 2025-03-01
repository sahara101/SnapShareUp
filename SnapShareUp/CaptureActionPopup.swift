import SwiftUI
import AppKit

struct CaptureActionPopup: View {
    let screenshot: NSImage
    let onUpload: () -> Void
    let onCopy: () -> Void
    let onEdit: (EditTool) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: screenshot)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .cornerRadius(8)
            
            HStack(spacing: 12) {
                Button("Upload & Copy URL") {
                    onUpload()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Copy Image Only") {
                    onCopy()
                }
                .buttonStyle(.bordered)
                
                Button("Edit") {
                    onEdit(.arrow) // Changed from .crop to .arrow
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
    }
}
