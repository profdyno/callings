import Foundation

/// Builds the markdown action checklist copied from the Open Callings view:
/// pending releases and calls grouped by assigned bishopric member, plus a
/// Ward Clerk section for app-created callings not yet in LCR.
enum ActionChecklistBuilder {

    struct Item {
        let assignee: BishopricMember
        let text: String
    }

    @MainActor
    static func markdown(from store: WardStore, date: Date = .now) -> String {
        var items: [Item] = []

        for entry in store.activeOpenCallings {
            guard let slot = store.slotsByID[entry.slotID],
                  let definition = store.definition(for: slot) else { continue }
            let calling = definition.name
            let holder = store.member(slot.memberID)?.name ?? slot.holderNameRaw

            // Release still pending announcement.
            if let holder, entry.releaseStatus == .open || entry.releaseStatus == .released {
                items.append(Item(
                    assignee: entry.releaseAssignedTo ?? .unassigned,
                    text: "- [ ] Release \(holder) — \(calling) (\(entry.releaseStatus.rawValue))"
                ))
            }

            // Call in progress, or nobody picked yet.
            if let newMember = store.member(entry.memberToBeCalledID)?.name,
               entry.callStatus == .selected || entry.callStatus == .accepted {
                items.append(Item(
                    assignee: entry.assignedTo,
                    text: "- [ ] Call \(newMember) — \(calling) (\(entry.callStatus.rawValue))"
                ))
            } else if entry.memberToBeCalledID == nil, entry.callStatus != .sustained {
                items.append(Item(
                    assignee: entry.assignedTo,
                    text: "- [ ] Select candidate — \(calling) (\(entry.candidateIDs.count) candidates)"
                ))
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var lines = ["# Calling Actions — \(formatter.string(from: date))"]

        let order: [BishopricMember] = [.bishop, .firstCounselor, .secondCounselor, .stake, .unassigned]
        for assignee in order {
            let assigned = items.filter { $0.assignee == assignee }
            guard !assigned.isEmpty else { continue }
            lines.append("")
            lines.append("**\(assignee.rawValue)**")
            lines.append(contentsOf: assigned.map(\.text))
        }

        // LCR bookkeeping for the ward clerk: callings created or deleted in
        // the app that LCR doesn't reflect yet.
        let clerkWork = store.data.callingDefinitions
            .filter { $0.isPending || $0.isMarkedForDeletion }
            .sorted { $0.organization.displayOrder != $1.organization.displayOrder
                ? $0.organization.displayOrder < $1.organization.displayOrder
                : $0.displayOrder < $1.displayOrder }
        if !clerkWork.isEmpty {
            lines.append("")
            lines.append("**Ward Clerk**")
            lines.append(contentsOf: clerkWork.map {
                $0.isMarkedForDeletion
                    ? "- [ ] Delete from LCR — \($0.name) (\($0.organization.rawValue))"
                    : "- [ ] Add to LCR — \($0.name) (\($0.organization.rawValue))"
            })
        }

        return lines.joined(separator: "\n")
    }
}
