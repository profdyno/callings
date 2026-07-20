import Foundation

/// Builds the action checklist shown on the Actions tab and copied as
/// markdown: pending releases and calls grouped by assigned bishopric member,
/// a Select Candidate section for callings still waiting on a pick, and a
/// Ward Clerk section for app-created callings not yet in LCR.
enum ActionChecklistBuilder {

    enum Kind {
        case release
        case call
        case selectCandidate
        case clerk
    }

    struct Item: Identifiable {
        let id = UUID()
        let kind: Kind
        /// "Release", "Call", "Select candidate", "Add to LCR", "Delete from LCR"
        let verb: String
        /// The member acted on (released holder / person to call); nil for
        /// select-candidate and clerk items.
        let member: String?
        let calling: String
        /// Status, candidate count, or organization — the parenthetical.
        let detail: String
        /// The open-calling entry behind release/call/select items, so the
        /// Actions view can change statuses and open the candidate picker.
        let entryID: UUID?
        let slotID: UUID?

        var markdownLine: String {
            let subject = member.map { "\(verb) \($0)" } ?? verb
            return "- [ ] \(subject) — \(calling) (\(detail))"
        }
    }

    struct Group: Identifiable {
        let title: String
        let items: [Item]
        var id: String { title }
    }

    static let selectCandidateTitle = "Select Candidate"
    static let wardClerkTitle = "Ward Clerk"

    /// The checklist as ordered sections; the markdown and the Actions table
    /// both render exactly this.
    @MainActor
    static func groups(from store: WardStore) -> [Group] {
        var byAssignee: [BishopricMember: [Item]] = [:]
        var selectCandidate: [Item] = []

        for entry in store.activeOpenCallings {
            guard let slot = store.slotsByID[entry.slotID],
                  let definition = store.definition(for: slot) else { continue }
            let calling = definition.name
            let holder = store.member(slot.memberID)?.name ?? slot.holderNameRaw

            // Release still pending announcement.
            if let holder, entry.releaseStatus == .open || entry.releaseStatus == .released {
                byAssignee[entry.releaseAssignedTo ?? .unassigned, default: []].append(Item(
                    kind: .release, verb: "Release", member: holder, calling: calling,
                    detail: entry.releaseStatus.rawValue, entryID: entry.id, slotID: nil
                ))
            }

            // Call in progress, or nobody picked yet.
            if let newMember = store.member(entry.memberToBeCalledID)?.name,
               entry.callStatus == .selected || entry.callStatus == .accepted {
                byAssignee[entry.assignedTo, default: []].append(Item(
                    kind: .call, verb: "Call", member: newMember, calling: calling,
                    detail: entry.callStatus.displayName, entryID: entry.id, slotID: nil
                ))
            } else if entry.memberToBeCalledID == nil, entry.callStatus != .sustained {
                selectCandidate.append(Item(
                    kind: .selectCandidate, verb: "Select candidate", member: nil, calling: calling,
                    detail: "\(entry.candidateIDs.count) candidates", entryID: entry.id, slotID: entry.slotID
                ))
            }
        }

        let order: [BishopricMember] = [.bishop, .firstCounselor, .secondCounselor, .execSecretary, .stake, .unassigned]
        var groups: [Group] = order.compactMap { assignee in
            guard let items = byAssignee[assignee] else { return nil }
            return Group(title: assignee.rawValue, items: items)
        }

        if !selectCandidate.isEmpty {
            groups.append(Group(title: selectCandidateTitle, items: selectCandidate))
        }

        // LCR bookkeeping for the ward clerk: callings created or deleted in
        // the app that LCR doesn't reflect yet.
        let clerkWork = store.data.callingDefinitions
            .filter { $0.isPending || $0.isMarkedForDeletion }
            .sorted { $0.organization.displayOrder != $1.organization.displayOrder
                ? $0.organization.displayOrder < $1.organization.displayOrder
                : $0.displayOrder < $1.displayOrder }
        if !clerkWork.isEmpty {
            groups.append(Group(title: wardClerkTitle, items: clerkWork.map {
                Item(
                    kind: .clerk,
                    verb: $0.isMarkedForDeletion ? "Delete from LCR" : "Add to LCR",
                    member: nil, calling: $0.name,
                    detail: $0.organization.rawValue, entryID: nil, slotID: nil
                )
            }))
        }

        return groups
    }

    @MainActor
    static func markdown(from store: WardStore, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var lines = ["# Calling Actions — \(formatter.string(from: date))"]

        for group in groups(from: store) {
            lines.append("")
            lines.append("**\(group.title)**")
            lines.append(contentsOf: group.items.map(\.markdownLine))
        }

        return lines.joined(separator: "\n")
    }
}
