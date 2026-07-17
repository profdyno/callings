import SwiftUI

struct WardCallingsView: View {
    @Environment(WardStore.self) private var store

    var body: some View {
        NavigationStack {
            Text("Ward Callings")
                .navigationTitle("Ward Callings")
        }
    }
}
