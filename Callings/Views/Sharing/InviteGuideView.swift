import SwiftUI

/// Owner's checklist for onboarding a bishopric member, with a pre-filled
/// setup-instructions email to send them.
struct InviteGuideView: View {
    @Environment(\.openURL) private var openURL

    private static let adminSteps: [(String, String)] = [
        ("Add them in App Store Connect",
         "appstoreconnect.apple.com → Users and Access → “+” → their name and Apple ID email → role “Sales” → limit access to the Ward Callings app → Invite."),
        ("Add them as a TestFlight tester",
         "App Store Connect → Ward Callings app → TestFlight → your internal group → add them. Apple emails them the TestFlight invitation."),
        ("Email them the setup instructions",
         "Use the button below — it opens a ready-to-send email with their steps."),
        ("Send the iCloud share invite",
         "Once they have the app installed: Sharing → Invite & Manage People… → send the invite to the email tied to their iPad's iCloud account."),
        ("They tap the invite link on their iPad",
         "The app opens and the ward data loads. Changes sync automatically from then on."),
    ]

    static let memberInstructions = """
    Getting set up with the Ward Callings app (takes about 10 minutes)

    You'll get three things from me/Apple — do these in order, all on your iPad:

    1. ACCEPT THE APPLE INVITATION
    - Watch your email for a message from Apple inviting you to the team.
    - Tap the link and sign in with your regular Apple ID (the one you use for the App Store). You do NOT need a developer account and there's nothing to pay — just accept.

    2. INSTALL TESTFLIGHT AND THE APP
    - On your iPad, install the free Apple app "TestFlight" from the App Store.
    - You'll get a second email inviting you to test "Ward Callings-Valley View". Open it on the iPad and tap "View in TestFlight", then Install.
    - When updates come out, TestFlight shows an Update button — install those when you see them.

    3. JOIN THE SHARED WARD DATA
    - Make sure your iPad is signed into iCloud (Settings → your name at the top).
    - I'll send you a share link in Messages or Mail. Open it ON THE IPAD — the Ward Callings app opens and loads the ward data. Give it a few seconds the first time.

    That's it. Anything you change syncs to all of us within a few seconds.

    WHAT YOU CAN DO: work candidate lists, assign who handles releases and calls, and move statuses along (Open/Released, Selected/Accepted). Two things stay with the bishop as owner: importing from LCR and marking things Announced/Sustained after sacrament meeting — those options appear grayed out for you, which is normal.

    IF SOMETHING LOOKS STUCK: open the Sharing screen (two-people icon, top left) and tap Sync Now. If it's really confused, Re-download All Data on that same screen resets your iPad from the shared copy.
    """

    var body: some View {
        Form {
            Section {
                ForEach(Array(Self.adminSteps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(index + 1). \(step.0)")
                            .font(.headline)
                        Text(step.1)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Your Steps (Owner)")
            }

            Section {
                Button {
                    sendInstructionsEmail()
                } label: {
                    Label("Email Setup Instructions…", systemImage: "envelope")
                }
                Button {
                    UIPasteboard.general.string = Self.memberInstructions
                } label: {
                    Label("Copy Instructions", systemImage: "doc.on.doc")
                }
            } footer: {
                Text("Opens a ready-to-send email with the member's setup steps — add their address and send.")
            }
        }
        .navigationTitle("Adding a Bishopric Member")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendInstructionsEmail() {
        let subject = "Ward Callings app — setup steps"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: Self.memberInstructions),
        ]
        if let url = components.url {
            openURL(url)
        }
    }
}
