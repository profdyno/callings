import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let wardMember = UTType(exportedAs: "com.profdyno.callings.member")
}

extension Member: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .wardMember)
    }
}

/// Draggable member list: either members without a calling or members with
/// callings (sortable by name or by time in current calling).
struct MemberColumnView: View {
    enum Mode {
        case needCallings
        case withCallings
    }

    @Environment(WardStore.self) private var store
    let mode: Mode
    @State private var sortByTenure = false
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mode == .needCallings ? "Members Need Callings" : "Members With Callings")
                    .font(.headline)
                Spacer()
                if mode == .withCallings {
                    Picker("Sort", selection: $sortByTenure) {
                        Text("Name").tag(false)
                        Text("Tenure").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
            }
            TextField("Filter…", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List(filteredMembers) { member in
                MemberRowView(member: member, showTenure: mode == .withCallings)
                    .draggable(member)
            }
            .listStyle(.plain)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var filteredMembers: [Member] {
        var members = mode == .needCallings ? store.membersNeedingCallings : store.membersWithCallings
        if mode == .withCallings && sortByTenure {
            members.sort { longestTenure($0) > longestTenure($1) }
        }
        if !searchText.isEmpty {
            members = members.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return members
    }

    private func longestTenure(_ member: Member) -> Int {
        store.slots(heldBy: member.id).compactMap { $0.monthsInCalling() }.max() ?? 0
    }
}

/// One draggable member row with calling/tenure context.
struct MemberRowView: View {
    @Environment(WardStore.self) private var store
    let member: Member
    var showTenure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(member.name)
                    .font(.subheadline)
                Spacer()
                if member.category != .none {
                    Text(member.category.label)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
            }
            if showTenure {
                let slots = store.slots(heldBy: member.id)
                if !slots.isEmpty {
                    Text(slots.compactMap { slot in
                        guard let name = store.definition(for: slot)?.name else { return nil }
                        let months = slot.monthsInCalling().map { " (\($0) mo)" } ?? ""
                        return name + months
                    }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
