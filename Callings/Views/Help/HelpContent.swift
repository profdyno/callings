import Foundation

/// One case per view and popup that shows a "?" help button. The content
/// switch is exhaustive, so a topic can't ship without copy.
enum HelpTopic {
    case members, ward, organizations, callingDetail, openCallings, actions
    case memberDetail, candidatePicker, addCalling, callingEditor, tagManager
    case sharing, importData, lcrWeb
}

struct HelpContent {
    struct Section {
        let heading: String?
        let bullets: [String]

        init(_ heading: String, _ bullets: [String]) {
            self.heading = heading
            self.bullets = bullets
        }

        init(_ bullets: [String]) {
            self.heading = nil
            self.bullets = bullets
        }
    }

    let title: String
    let summary: String
    let sections: [Section]
}

extension HelpTopic {

    var content: HelpContent {
        switch self {

        case .members:
            return HelpContent(
                title: "Members",
                summary: "Every active member on the roster with their class, callings, and tag.",
                sections: [
                    .init([
                        "Search matches names, class assignments, and tags — type “Priests” or “Moving Soon” to filter.",
                        "Tap a member's name for their full profile, contact buttons, and callings.",
                        "The Tag column edits in place — tap it to set or clear a member's tag.",
                    ]),
                    .init("Tags", [
                        "The tag icon in the toolbar opens the tag manager to add or delete custom tags.",
                        "Tags sync to every iPad sharing the ward.",
                    ]),
                ]
            )

        case .ward:
            return HelpContent(
                title: "Ward Callings",
                summary: "The whole ward at a glance — one board per organization. The quickest place to start a release or a call.",
                sections: [
                    .init("Getting Around", [
                        "Swipe left and right to move between organization boards.",
                        "Tap a board's title to jump to that organization's workflow table.",
                    ]),
                    .init("Working a Calling", [
                        "Tap a calling's name to pick candidates for it.",
                        "Tap a member's name for their profile and contact buttons.",
                        "Long-press a row for more: full details, member details, add or remove from Open Callings, and Edit Criteria & Order.",
                    ]),
                    .init("Colors", [
                        "Red calling — a change is in progress on Open Callings.",
                        "Orange calling — created in the app but not in LCR yet.",
                        "Strikethrough — marked for deletion.",
                        "With the toolbar filters on: red member — vacant; orange member — over the tenure threshold.",
                    ]),
                    .init("Toolbar", [
                        "New Calling adds a calling to any organization.",
                        "The Vacant & Open and Over X mo toggles highlight what needs attention; the months menu sets the threshold.",
                    ]),
                ]
            )

        case .organizations:
            return HelpContent(
                title: "Organizations",
                summary: "The full workflow table for one organization — a release and a call each move forward inside their row.",
                sections: [
                    .init([
                        "Pick an organization in the sidebar.",
                        "Current (Release) walks the release forward: Open → Released → Announced.",
                        "Candidates opens the candidate picker for that calling.",
                        "To Be Called picks who to call and walks the call forward: Selected → Called → Sustained.",
                        "The two Assigned columns say which bishopric member owns the release and the call.",
                    ]),
                    .init("Good to Know", [
                        "Announced and Sustained happen in sacrament meeting, so only the owner's iPad can set them — they're grayed out for everyone else.",
                        "When a status reaches Called or Released, the item is handed to the Exec Secretary automatically.",
                        "The slider icon edits a calling's candidate criteria and display order.",
                        "When both the release and the call finish, the change completes and moves to the archive.",
                    ]),
                ]
            )

        case .callingDetail:
            return HelpContent(
                title: "Calling Details",
                summary: "One calling with its candidate list and the members who could fill it.",
                sections: [
                    .init("Candidates", [
                        "Drag members from the columns on the right and drop them on Candidates — or tap + to pick from the filtered list.",
                        "Swipe a candidate left to remove them.",
                    ]),
                    .init("Member Columns", [
                        "Members Need Callings lists everyone without a calling.",
                        "Members With Callings can sort by tenure to find who has served longest.",
                        "Tap any member for their profile.",
                    ]),
                    .init("Status", [
                        "The status box edits everything for this calling — assignments, member to call, and both statuses.",
                    ]),
                ]
            )

        case .openCallings:
            return HelpContent(
                title: "Open Callings",
                summary: "Every calling change in flight — one row per release/call, edited directly in the table.",
                sections: [
                    .init([
                        "Start a change by tapping a calling on the Ward page, or Add to Open Callings from its long-press menu.",
                        "The filter bar narrows by group, status, or assignee — Clear brings everything back.",
                        "The trash button deletes a change; long-press a row to archive it instead.",
                    ]),
                    .init("Archived", [
                        "The Archived toggle in the toolbar shows completed and archived changes — a history of who replaced whom.",
                    ]),
                ]
            )

        case .actions:
            return HelpContent(
                title: "Actions",
                summary: "The to-do list for bishopric meeting: who releases whom, who extends which call, which callings still need a candidate, and what the clerk records in LCR.",
                sections: [
                    .init([
                        "Rows are grouped by owner — each bishopric member sees their releases and calls.",
                        "Change a status right here with its menu.",
                        "Select Candidate lists callings with nobody picked yet — tap Pick… to choose.",
                        "Ward Clerk lists LCR bookkeeping: callings to add or delete.",
                    ]),
                    .init("Good to Know", [
                        "Once something reaches Called or Released it moves to the Exec Secretary automatically for the sacrament-meeting agenda.",
                        "The share icon copies this exact list as a markdown checklist — paste it into Notes or a message.",
                    ]),
                ]
            )

        case .memberDetail:
            return HelpContent(
                title: "Member Details",
                summary: "One member's profile, contact info, callings, and candidacies.",
                sections: [
                    .init([
                        "Tap the phone icon to call, the message bubble to text, or the email address to write them.",
                        "Tag edits in place.",
                        "Rows under Candidate For open that calling's candidate picker.",
                    ]),
                ]
            )

        case .candidatePicker:
            return HelpContent(
                title: "Pick Candidates",
                summary: "Choose who to consider for this calling — tap members to add or remove them.",
                sections: [
                    .init([
                        "The list only shows members matching the calling's criteria (age, gender, priesthood, class) — flip on All Members to see everyone.",
                        "Tap ⓘ for a member's profile before deciding.",
                    ]),
                    .init("Good to Know", [
                        "If the list looks wrong, edit the criteria with the slider icon.",
                        "Start as TBD opens the calling change without naming candidates yet.",
                        "Closing without picking anyone creates no calling change.",
                    ]),
                ]
            )

        case .addCalling:
            return HelpContent(
                title: "New Calling",
                summary: "Add a calling that doesn't exist in the app yet.",
                sections: [
                    .init([
                        "Pick the organization and group, then tap + next to the calling it should appear after, and name it.",
                        "New callings show in orange until the ward clerk adds them in LCR — that step appears on the Actions tab.",
                        "The next import matches the LCR calling to the one created here.",
                    ]),
                ]
            )

        case .callingEditor:
            return HelpContent(
                title: "Criteria & Order",
                summary: "Control who the candidate picker suggests for this calling and where it sorts.",
                sections: [
                    .init([
                        "Criteria (gender, priesthood, age, class) filter the candidate picker's list.",
                        "Display order sorts within the group — lower numbers first.",
                        "Deleting an LCR calling marks it and adds a Ward Clerk action; deleting an orange pending calling removes it immediately.",
                    ]),
                ]
            )

        case .tagManager:
            return HelpContent(
                title: "Manage Tags",
                summary: "The tag list shared by every iPad on the ward.",
                sections: [
                    .init([
                        "Built-in tags are fixed; add custom tags below.",
                        "Deleting a tag clears it from every member who has it.",
                        "Changes sync ward-wide.",
                    ]),
                ]
            )

        case .sharing:
            return HelpContent(
                title: "Sharing",
                summary: "Sync this ward across the bishopric's iPads.",
                sections: [
                    .init([
                        "The owner (bishop) starts sharing and invites the others — Adding a Bishopric Member… walks through the whole invite.",
                        "Sync Now forces an immediate fetch.",
                    ]),
                    .init("If Something Looks Stuck", [
                        "Check the Sync Log for what's been happening.",
                        "Re-download All Data resets this iPad from the shared copy — local edits that haven't synced yet are lost.",
                    ]),
                ]
            )

        case .importData:
            return HelpContent(
                title: "Import",
                summary: "Load member and calling data from LCR — done on the owner's iPad.",
                sections: [
                    .init([
                        "Fetch from LCR… signs in to LCR and extracts the reports directly.",
                        "Choose PDF… loads an LCR report saved as PDF. Save PDFs on the iPad — laptop-saved PDFs can come out unreadable.",
                        "Every import shows a preview of the changes before anything applies.",
                    ]),
                    .init("Placeholders", [
                        "Calling holders who aren't on the roster show as placeholders until a member-list import matches them.",
                    ]),
                ]
            )

        case .lcrWeb:
            return HelpContent(
                title: "Fetch from LCR",
                summary: "Sign in to LCR and pull reports straight into the app.",
                sections: [
                    .init([
                        "Sign in, wait for the report to finish loading, then tap Extract.",
                        "Switch between Member List and Ward Callings with the picker at the top.",
                    ]),
                    .init("If It Hangs", [
                        "⋯ → Sign Out & Reset clears the session for a fresh login.",
                        "Copy Page Snapshot copies a structure-only outline of the page (no member data) for troubleshooting.",
                    ]),
                ]
            )
        }
    }
}
