import Foundation

/// The fixed set of ward organizations, in display order.
enum OrganizationKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case bishopric = "Bishopric"
    case eldersQuorum = "Elders Quorum"
    case reliefSociety = "Relief Society"
    case wardMissionaries = "Ward Missionaries"
    case templeAndFamilyHistory = "Temple and Family History"
    case sundaySchool = "Sunday School"
    case aaronicPriesthoodQuorums = "Aaronic Priesthood Quorums"
    case youngWomen = "Young Women"
    case primary = "Primary"
    case youngSingleAdult = "Young Single Adult"
    case otherCallings = "Other Callings"

    var id: String { rawValue }

    var displayOrder: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    /// Matches an organization section header from the LCR Ward Callings PDF.
    /// LCR uses a few alternate spellings/prefixes for the same organization.
    static func match(headerText: String) -> OrganizationKind? {
        let text = headerText.trimmingCharacters(in: .whitespaces)
        if let exact = OrganizationKind(rawValue: text) { return exact }
        let lowered = text.lowercased()
        switch lowered {
        case let s where s.contains("bishopric"): return .bishopric
        case let s where s.contains("elders quorum"): return .eldersQuorum
        case let s where s.contains("relief society"): return .reliefSociety
        case let s where s.contains("mission"): return .wardMissionaries
        case let s where s.contains("temple") && s.contains("family history"): return .templeAndFamilyHistory
        case let s where s.contains("sunday school"): return .sundaySchool
        case let s where s.contains("aaronic priesthood"): return .aaronicPriesthoodQuorums
        case let s where s.contains("young women"): return .youngWomen
        case let s where s.contains("primary"): return .primary
        case let s where s.contains("young single adult"): return .youngSingleAdult
        case let s where s.contains("other"): return .otherCallings
        default: return nil
        }
    }
}
