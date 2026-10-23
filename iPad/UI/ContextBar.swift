import SwiftUI

/// Quick actions for the selection, floating at the bottom.
struct ContextBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let c = model.canvas
        if !c.selection.isEmpty && !model.isEditingText {
            HStack(spacing: 2) {
                if c.selection.count == 1, !c.selectionHasLocked {
                    bar("pencil", "Edit") { c.editSelection(nil) }
                }
                bar("plus.square.on.square", "Duplicate") { c.duplicateSelection() }
                bar("doc.on.doc", "Copy") { c.copyToPasteboard() }
                if c.selectedShapes.count > 1 { bar("square.on.square", "Group") { c.groupSelection() } }
                if c.selectedShapes.contains(where: { $0.group != nil }) { bar("square.on.square.dashed", "Ungroup") { c.ungroupSelection() } }
                bar("square.3.layers.3d.top.filled", "Bring to Front") { c.bringToFront(nil) }
                bar(c.selectionHasUnlocked ? "lock" : "lock.open", c.selectionHasUnlocked ? "Lock" : "Unlock") {
                    if c.selectionHasUnlocked { c.lockSelection(nil) } else { c.unlockSelection(nil) }
                }
                bar("trash", "Delete", tint: .red) { c.deleteSelection() }
                    .disabled(!c.canDelete)
            }
            .padding(6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color(Tok.panelOutline), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private func bar(_ symbol: String, _ title: String, tint: Color? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 42, height: 40)
                .foregroundStyle(tint ?? Color(Tok.iconDefault))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
