import SwiftUI

/// Workflow-stage quick filters shared by Open Callings and Actions.
enum StageFilter: String, CaseIterable, Identifiable {
    case approve = "Need to Approve"
    case releaseCall = "Need to Release/Call"
    case announceSustain = "Need to Announce/Sustain"

    var id: String { rawValue }

    /// The release-ladder status this stage corresponds to.
    var releaseStatus: ReleaseStatus {
        switch self {
        case .approve: .proposed
        case .releaseCall: .approved
        case .announceSustain: .released
        }
    }

    /// The call-ladder status this stage corresponds to.
    var callStatus: CallStatus {
        switch self {
        case .approve: .proposed
        case .releaseCall: .approved
        case .announceSustain: .called
        }
    }

    /// An entry matches when EITHER of its ladders sits at this stage.
    func matches(_ entry: OpenCalling) -> Bool {
        entry.releaseStatus == releaseStatus || entry.callStatus == callStatus
    }
}

/// The chip row above the Open Callings and Actions tables: stage toggles,
/// person toggles, and view-specific trailing content (menus, Clear).
struct WorkflowFilterBar<Trailing: View>: View {
    @Binding var stage: StageFilter?
    @Binding var person: BishopricMember?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StageFilter.allCases) { option in
                    toggleChip(option.rawValue, isOn: stage == option) {
                        stage = stage == option ? nil : option
                    }
                }
                Divider()
                    .frame(height: 20)
                ForEach([BishopricMember.bishop, .firstCounselor, .secondCounselor]) { member in
                    toggleChip(member.rawValue, isOn: person == member) {
                        person = person == member ? nil : member
                    }
                }
                Divider()
                    .frame(height: 20)
                trailing
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func toggleChip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isOn ? Color.accentColor : Color(.systemGray5), in: Capsule())
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
