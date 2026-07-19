import Foundation

enum Gender: String, Codable, Hashable {
    case male = "M"
    case female = "F"
}

/// Priesthood as reported by the LCR member list, which is track-level only.
enum PriesthoodTrack: String, Codable, CaseIterable, Hashable {
    case none = ""
    case aaronic = "Aaronic"
    case melchizedek = "Melchizedek"

    /// Rank used for "minimum priesthood" candidate criteria comparisons.
    var rank: Int {
        switch self {
        case .none: return 0
        case .aaronic: return 1
        case .melchizedek: return 2
        }
    }

    var label: String { self == .none ? "None" : rawValue }
}

/// User-maintained category shown/edited in the candidate picker.
enum MemberCategory: Codable, Hashable {
    case none
    case notActive
    case doNotCall
    case movingSoon
    case other(String)

    var label: String {
        switch self {
        case .none: return ""
        case .notActive: return "Not Active"
        case .doNotCall: return "Do Not Call"
        case .movingSoon: return "Moving Soon"
        case .other(let text): return text
        }
    }

    static var standardCases: [MemberCategory] { [.none, .notActive, .doNotCall, .movingSoon] }
}

struct Member: Codable, Identifiable, Hashable {
    var id = UUID()
    /// "Last, First Middle" as printed in LCR reports.
    var name: String
    var age: Int?
    var gender: Gender?
    var email: String?
    var phone: String?
    var priesthood: PriesthoodTrack = .none
    /// Aaronic/Melchizedek office from the roster ("Deacon"…"High Priest").
    /// Optional String — new report column; older saved data lacks it.
    var priesthoodOffice: String?
    var moveInDate: Date?
    /// "Active", "Canceled", "Expired", "Expires next month", …
    var templeRecommendStatus: String?
    var classAssignments: [String] = []
    var category: MemberCategory = .none
    /// False when the member disappeared from a roster re-import (moved/records out).
    var isActiveOnRoster: Bool = true
    /// True when created as a placeholder from a callings-PDF holder name
    /// that could not be matched to the roster.
    var isPlaceholder: Bool = false

    var lastName: String {
        name.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? name
    }

    var firstNames: String {
        guard let comma = name.firstIndex(of: ",") else { return "" }
        return String(name[name.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
    }

    /// "First Last" for friendlier display in tight columns.
    var displayName: String {
        firstNames.isEmpty ? name : "\(firstNames) \(lastName)"
    }
}
