import Foundation

/// Default display order and candidate criteria applied to newly imported
/// calling definitions. User edits are preserved on re-import, so these only
/// run when a definition is first created.
enum CallingSeedRules {

    /// Display order from calling-name keywords: President first, then
    /// counselors, secretary, and the rest, matching the spec's required order.
    static func displayOrder(for name: String) -> Int {
        let lowered = name.lowercased()
        let rules: [(keyword: String, order: Int)] = [
            ("bishop", 0), ("president", 0),
            ("first counselor", 10), ("first assistant", 10),
            ("second counselor", 20), ("second assistant", 20),
            ("assistant secretary", 40),
            ("secretary", 30),
            ("adviser", 50), ("advisor", 50),
            ("coordinator", 55),
            ("leader", 60),
            ("teacher", 70),
            ("specialist", 80),
        ]
        for rule in rules where lowered.contains(rule.keyword) {
            return rule.order
        }
        return 100
    }

    /// Default candidate criteria by organization and calling name.
    static func criteria(for name: String, organization: OrganizationKind, subgroup: String?) -> CandidateCriteria {
        var criteria = CandidateCriteria()
        let lowered = name.lowercased()
        let sub = (subgroup ?? "").lowercased()

        switch organization {
        case .bishopric:
            criteria.gender = .male
            criteria.minimumPriesthood = .melchizedek
        case .eldersQuorum:
            criteria.gender = .male
            criteria.minimumPriesthood = lowered.contains("president") || lowered.contains("counselor")
                ? .melchizedek : .aaronic
            criteria.minAge = 18
        case .reliefSociety:
            criteria.gender = .female
            criteria.minAge = 18
        case .aaronicPriesthoodQuorums:
            if sub.contains("adult leaders") || lowered.contains("adviser") || lowered.contains("specialist") {
                criteria.minAge = 18
            } else {
                // Quorum presidencies are held by the young men themselves.
                criteria.gender = .male
                criteria.minimumPriesthood = .aaronic
                criteria.minAge = 11
                criteria.maxAge = 18
            }
        case .youngWomen:
            criteria.gender = .female
            if sub.contains("class presidency") {
                // Class presidencies are held by the young women themselves.
                criteria.minAge = 11
                criteria.maxAge = 18
                if !sub.isEmpty, let className = subgroup?.replacingOccurrences(of: " Class Presidency", with: ""),
                   sub.contains("class presidency") {
                    criteria.requiredClassAssignments = [className]
                }
            } else {
                criteria.minAge = 18
            }
        case .primary, .sundaySchool, .wardMissionaries, .templeAndFamilyHistory,
             .youngSingleAdult, .otherCallings:
            criteria.minAge = 18
        }
        return criteria
    }

    /// Applies both rules to a freshly created definition.
    static func apply(to definition: inout CallingDefinition) {
        definition.displayOrder = displayOrder(for: definition.name)
        definition.criteria = criteria(
            for: definition.name,
            organization: definition.organization,
            subgroup: definition.subgroup
        )
    }
}
