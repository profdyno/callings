import SwiftUI

/// The app-wide leading toolbar: Sharing button, the ⋯ menu with Import and
/// the dark-background toggle, and the tab's help button. Applied on every
/// tab so sharing and import are reachable from anywhere.
struct AppToolbarModifier: ViewModifier {
    let helpTopic: HelpTopic?
    @State private var showingSharing = false
    @State private var showingImport = false
    @AppStorage("appearanceDark") private var appearanceDark = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingSharing = true
                    } label: {
                        Label("Sharing", systemImage: "person.2")
                    }
                    Menu {
                        Button {
                            showingImport = true
                        } label: {
                            Label("Import…", systemImage: "square.and.arrow.down")
                        }
                        Toggle(isOn: $appearanceDark) {
                            Label("Dark Background", systemImage: appearanceDark ? "moon.fill" : "moon")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    if let helpTopic {
                        HelpButton(topic: helpTopic)
                    }
                }
            }
            .sheet(isPresented: $showingSharing) {
                SharingView()
            }
            .sheet(isPresented: $showingImport) {
                ImportView()
            }
    }
}

extension View {
    func appToolbar(help topic: HelpTopic? = nil) -> some View {
        modifier(AppToolbarModifier(helpTopic: topic))
    }
}
