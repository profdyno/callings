import SwiftUI

struct ImportView: View {
    @Environment(WardStore.self) private var store

    var body: some View {
        NavigationStack {
            Text("Import")
                .navigationTitle("Import")
        }
    }
}
