import Foundation

/// Criteria describing which members are eligible candidates for a calling.
struct CandidateCriteria: Codable, Hashable {
    var gender: Gender?
    var minAge: Int?
    var maxAge: Int?
    var minimumPriesthood: PriesthoodTrack?
    /// Member must have at least one of these class assignments (empty = no requirement).
    var requiredClassAssignments: [String] = []
    var allowMultipleCallings: Bool = true

    func matches(_ member: Member) -> Bool {
        if let gender, member.gender != gender { return false }
        if let minAge, let age = member.age, age < minAge { return false }
        if let maxAge, let age = member.age, age > maxAge { return false }
        if let minimumPriesthood, member.priesthood.rank < minimumPriesthood.rank { return false }
        if !requiredClassAssignments.isEmpty {
            let memberClasses = Set(member.classAssignments.map { $0.lowercased() })
            let required = requiredClassAssignments.map { $0.lowercased() }
            if !required.contains(where: memberClasses.contains) { return false }
        }
        return true
    }
}

/// A calling position type within an organization (e.g. "Elders Quorum President").
struct CallingDefinition: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var organization: OrganizationKind
    /// Sub-heading within the organization in the LCR PDF (e.g. "Priests Quorum Presidency").
    var subgroup: String?
    /// Sort order within the organization: President first, then counselors, secretary, others.
    var displayOrder: Int = 100
    var criteria = CandidateCriteria()
    /// True for ward-defined custom callings (prefixed "* " in the LCR export).
    var isCustom: Bool = false

    /// Stable identity for reconciling across imports.
    var importKey: String {
        "\(organization.rawValue)|\(subgroup ?? "")|\(name)".lowercased()
    }

    /// Calling name for display inside its own organization's group, with the
    /// redundant organization prefix removed ("Elders Quorum President" shown
    /// under Elders Quorum becomes "President").
    var nameWithinOrganization: String {
        let prefix = organization.rawValue
        guard name.count > prefix.count,
              name.lowercased().hasPrefix(prefix.lowercased()) else { return name }
        let stripped = String(name.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? name : stripped
    }
}
