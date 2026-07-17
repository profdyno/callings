import SwiftUI

struct OpenCallingsView: View {
    @Environment(WardStore.self) private var store

    var body: some View {
        NavigationStack {
            Text("Open Callings")
                .navigationTitle("Open Callings")
        }
    }
}
