import Foundation

enum BishopricMember: String, Codable, CaseIterable, Identifiable {
    case unassigned = "Unassigned"
    case bishop = "Bishop"
    case firstCounselor = "1st Counselor"
    case secondCounselor = "2nd Counselor"
    case stake = "Stake"

    var id: String { rawValue }
}

/// Status ladder for releasing the current holder.
enum ReleaseStatus: String, Codable, CaseIterable, Identifiable {
    case none = "—"
    case open = "Open"           // red
    case released = "Released"   // blue
    case announced = "Announced" // color removed

    var id: String { rawValue }

    var next: ReleaseStatus {
        switch self {
        case .none: return .open
        case .open: return .released
        case .released: return .announced
        case .announced: return .announced
        }
    }
}

/// Status ladder for calling the new member.
enum CallStatus: String, Codable, CaseIterable, Identifiable {
    case none = "—"
    case selected = "Selected"   // yellow
    case accepted = "Accepted"   // green
    case sustained = "Sustained" // color removed

    var id: String { rawValue }

    var next: CallStatus {
        switch self {
        case .none: return .selected
        case .selected: return .accepted
        case .accepted: return .sustained
        case .sustained: return .sustained
        }
    }
}

/// A working entry in the Open Callings table tracking a release/call in progress.
struct OpenCalling: Codable, Identifiable, Hashable {
    var id = UUID()
    var slotID: UUID
    /// Who conducts the call ("Assigned (Call)").
    var assignedTo: BishopricMember = .unassigned
    /// Who conducts the release ("Assigned (Release)"). Optional so data
    /// saved before this field existed still decodes; nil = unassigned.
    var releaseAssignedTo: BishopricMember?
    var releaseStatus: ReleaseStatus = .open
    var memberToBeCalledID: UUID?
    var callStatus: CallStatus = .none
    var candidateIDs: [UUID] = []
    var notes: String = ""
    var createdAt = Date()

    // Archive snapshot — denormalized so history survives re-imports that
    // replace slots and members.
    var isArchived: Bool = false
    var archivedAt: Date?
    var snapshotCallingName: String?
    var snapshotOrganization: String?
    var snapshotPreviousHolder: String?
    var snapshotNewHolder: String?
}
