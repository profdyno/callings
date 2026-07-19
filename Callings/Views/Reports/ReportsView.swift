import SwiftUI

/// Reports: members who need callings and members with callings, side by
/// side, with the member category editable in place.
struct ReportsView: View {
    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 12) {
                MemberColumnView(mode: .needCallings, editableCategory: true)
                MemberColumnView(mode: .withCallings, editableCategory: true)
            }
            .padding(12)
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
            .appToolbar()
        }
    }
}
