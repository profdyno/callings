import SwiftUI

/// Toolbar "?" button that pops the help for one view or sheet.
struct HelpButton: View {
    let topic: HelpTopic
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label("Help", systemImage: "questionmark.circle")
        }
        .popover(isPresented: $showing) {
            HelpPopover(content: topic.content)
                .presentationCompactAdaptation(.popover)
        }
        .task {
            // "-help" launch arg auto-opens the visible view's help so
            // simulator screenshots can capture it. Presenting before the
            // toolbar button has an anchor crashes UIKit, hence the delay.
            guard ProcessInfo.processInfo.arguments.contains("-help") else { return }
            try? await Task.sleep(for: .seconds(1))
            showing = true
        }
    }
}

private struct HelpPopover: View {
    let content: HelpContent

    var body: some View {
        // Short topics fit as-is; long ones scroll.
        ViewThatFits(in: .vertical) {
            body_
            ScrollView { body_ }
        }
        .frame(width: 420)
        .frame(maxHeight: 580)
    }

    private var body_: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(content.title)
                .font(.title3.bold())
            Text(content.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(content.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    if let heading = section.heading {
                        Text(heading)
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(bullet)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
