import SwiftUI

/// The right-hand panel: Format, Arrange, Layers and Library tabs.
struct InspectorHost: View {
    @ObservedObject var model: EditorModel
    @Binding var tab: InspectorTab

    var body: some View {
        VStack(spacing: 0) {
            Picker("Panel", selection: $tab) {
                ForEach(InspectorTab.allCases) { t in Label(t.title, systemImage: t.symbol).tag(t) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .padding(12)
            Divider()
            Group {
                switch tab {
                case .format: FormatTab(model: model)
                case .arrange: ArrangeTab(model: model)
                case .layers: LayersTab(model: model)
                case .library: LibraryTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(Tok.windowBG))
    }
}
