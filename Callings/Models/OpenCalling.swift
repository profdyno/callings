import Foundation

enum BishopricMember: String, Codable, CaseIterable, Identifiable {
    case unassigned = "Unassigned"
    case bishop = "Bishop"
    case firstCounselor = "1st Counselor"
    case secondCounselor = "2nd Counselor"
    case execSecretary = "Exec Secretary"
    case stake = "Stake"

    var id: String { rawValue }
}

/// Status ladder for releasing the current holder.
enum ReleaseStatus: String, Codable, CaseIterable, Identifiable {
    case none = "—"
    case proposed = "Proposed"   // red
    case approved = "Approved"   // purple
    case released = "Released"   // blue
    case announced = "Announced" // color removed

    var id: String { rawValue }

    var next: ReleaseStatus {
        switch self {
        case .none: return .proposed
        case .proposed: return .approved
        case .approved: return .released
        case .released: return .announced
        case .announced: return .announced
        }
    }

    /// Decodes current rawValues plus the pre-approval-step legacy values
    /// still present in saved JSON and CloudKit records.
    init(persisted raw: String) {
        self = ReleaseStatus(rawValue: raw)
            ?? (raw == "Open" ? .proposed : .none)
    }

    init(from decoder: Decoder) throws {
        self.init(persisted: try decoder.singleValueContainer().decode(String.self))
    }
}

/// Status ladder for calling the new member.
enum CallStatus: String, Codable, CaseIterable, Identifiable {
    case none = "—"
    case proposed = "Proposed"   // yellow
    case approved = "Approved"   // purple
    case called = "Called"       // green
    case sustained = "Sustained" // color removed

    var id: String { rawValue }

    var next: CallStatus {
        switch self {
        case .none: return .proposed
        case .proposed: return .approved
        case .approved: return .called
        case .called: return .sustained
        case .sustained: return .sustained
        }
    }

    /// Decodes current rawValues plus the pre-approval-step legacy values
    /// still present in saved JSON and CloudKit records.
    init(persisted raw: String) {
        switch raw {
        case "Selected": self = .proposed
        case "Accepted": self = .called
        default: self = CallStatus(rawValue: raw) ?? .none
        }
    }

    init(from decoder: Decoder) throws {
        self.init(persisted: try decoder.singleValueContainer().decode(String.self))
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
    var releaseStatus: ReleaseStatus = .proposed
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
