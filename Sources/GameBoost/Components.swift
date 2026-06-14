import SwiftUI

/// A small "i" button that reveals an explanation in a popover. Used throughout
/// to explain what each metric/action does (and its honest caveats) on demand,
/// without cluttering the UI.
struct InfoButton: View {
    let title: String
    let text: String
    @State private var show = false

    var body: some View {
        Button { show.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(text)
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 270)
        }
    }
}

/// A muted one-line (wrapping) intro caption for the top of a section/tab.
struct IntroText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
