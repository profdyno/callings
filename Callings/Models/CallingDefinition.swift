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
    /// Sort order within the organization: President first, then counselors,
    /// secretary, others. Fractional so user-created callings can slot halfway
    /// between existing ones.
    var displayOrder: Double = 100
    var criteria = CandidateCriteria()
    /// True for ward-defined custom callings (prefixed "* " in the LCR export).
    var isCustom: Bool = false
    /// True for callings created in the app that haven't appeared in an LCR
    /// import yet — shown in orange until the ward clerk adds them to LCR.
    /// Optional so data saved before this field existed still decodes.
    var isPendingLCR: Bool?

    var isPending: Bool { isPendingLCR ?? false }

    /// True when the user deleted an LCR-backed calling in the app: shown
    /// struck through in red until the ward clerk removes it in LCR and a
    /// re-import no longer contains it. Optional for decode compatibility.
    var isPendingDeletion: Bool?

    var isMarkedForDeletion: Bool { isPendingDeletion ?? false }

    /// Stable identity for reconciling across imports.
    var importKey: String {
        "\(organization.rawValue)|\(subgroup ?? "")|\(name)".lowercased()
    }

    /// Calling name for display inside its own organization's group, with
    /// redundant context stripped so more fits on screen. Display-only —
    /// matching and the Open Callings view use the full `name`.
    ///
    /// Pipeline (each step falls back to the previous result rather than
    /// producing an empty string):
    /// 1. Strip a "Ward <org>", "<org>", or subgroup-stem prefix
    ///    ("Priests Quorum President" under its presidency → "President").
    /// 2. Under the Activities/Service subgroups, drop the leading
    ///    "Activity"/"Service" ("Activity Coordinator" → "Coordinator").
    /// 3. Abbreviate "Assistant" → "Asst".
    var nameWithinOrganization: String {
        var result = name

        // 1. Redundant prefixes, longest candidates first.
        var prefixes = ["Ward \(organization.rawValue)", organization.rawValue]
        if let subgroup {
            var stem = subgroup
            for suffix in [" Class Presidency", " Presidency", " Adult Leaders"] where stem.hasSuffix(suffix) {
                // "Gatherers of Light Class Presidency" keeps "Class" in its stem.
                stem = suffix == " Class Presidency"
                    ? String(stem.dropLast(" Presidency".count))
                    : String(stem.dropLast(suffix.count))
            }
            prefixes.append(stem)
        }
        for prefix in prefixes.sorted(by: { $0.count > $1.count }) {
            if result.count > prefix.count, result.lowercased().hasPrefix(prefix.lowercased() + " ") {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // 2. Words redundant with the Activities/Service subgroup headers
        // (may follow "Assistant": "Assistant Service Coordinator").
        if let subgroup {
            let redundant = ["Activities": "Activity", "Service": "Service"]
            if let word = redundant[subgroup] {
                let stripped = result
                    .replacingOccurrences(of: #"\b\#(word)\b\s?"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { result = stripped }
            }
        }

        // 3. Abbreviations.
        result = result.replacingOccurrences(
            of: #"\bAssistant\b"#, with: "Asst", options: .regularExpression
        )

        return result.isEmpty ? name : result
    }

    /// Display name for a subgroup header within an organization
    /// ("Activities" in Elders Quorum / Relief Society reads "Activities Committee").
    static func subgroupDisplayName(_ subgroup: String, organization: OrganizationKind) -> String {
        guard organization == .eldersQuorum || organization == .reliefSociety else { return subgroup }
        switch subgroup {
        case "Activities": return "Activities Committee"
        case "Service": return "Service Committee"
        default: return subgroup
        }
    }
}
