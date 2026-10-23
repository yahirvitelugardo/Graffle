import SwiftUI

struct CanvasRepresentable: UIViewRepresentable {
    let canvas: CanvasView
    func makeUIView(context: Context) -> CanvasView { canvas }
    func updateUIView(_ uiView: CanvasView, context: Context) {}
}
