import SwiftUI
import CloudKit
import UIKit

/// Opt-in sharing screen: the owner starts sharing and invites the
/// bishopric; a joined participant sees their status; solo mode explains
/// both paths.
struct SharingView: View {
    @Environment(WardStore.self) private var store
    @Environment(SyncService.self) private var syncService
    @Environment(ShareCoordinator.self) private var shareCoordinator
    @State private var presentingShareSheet = false
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmingReset = false
    @State private var confirmingResync = false
    @State private var resyncing = false
    @State private var repairReport: WardDataRepair.Report?
    @State private var adopting = false

    var body: some View {
        NavigationStack {
            Form {
                switch syncService.role {
                case .solo:
                    soloSection
                case .owner:
                    ownerSection
                case .participant:
                    participantSection
                }

                if syncService.role != .solo {
                    Section {
                        Button {
                            confirmingResync = true
                        } label: {
                            if resyncing {
                                ProgressView()
                            } else {
                                Label("Re-download All Data…", systemImage: "icloud.and.arrow.down")
                            }
                        }
                        .disabled(resyncing)
                    } footer: {
                        Text("Replaces everything on this iPad with the shared ward data from iCloud. Use this if this iPad looks out of step with the others. Changes made here that never synced are lost.")
                    }
                }

                Section {
                    Button {
                        repairReport = store.repairDuplicates()
                    } label: {
                        Label("Check for Duplicate Callings", systemImage: "arrow.triangle.merge")
                    }
                    if let repairReport {
                        Label(
                            repairReport.isEmpty
                                ? "No duplicates found."
                                : repairReport.summary,
                            systemImage: repairReport.isEmpty ? "checkmark.circle" : "wrench.and.screwdriver"
                        )
                        .font(.footnote)
                        .foregroundStyle(repairReport.isEmpty ? .secondary : .primary)
                    }
                } header: {
                    Text("Repair")
                } footer: {
                    Text("Runs automatically at launch. Collapses callings that appear twice, then re-import the Ward Callings report to restore the exact seat counts.")
                }

                if syncService.role != .solo {
                    Section {
                        NavigationLink {
                            SyncLogView()
                        } label: {
                            Label("Sync Log", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .task {
                // Surface what the launch pass already collapsed.
                if repairReport == nil { repairReport = store.lastRepairReport }
            }
            .navigationTitle("Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HelpButton(topic: .sharing)
                }
            }
            .confirmationDialog(
                "Replace this iPad's data with the shared ward from iCloud?",
                isPresented: $confirmingResync,
                titleVisibility: .visible
            ) {
                Button("Re-download All Data", role: .destructive) {
                    resyncing = true
                    Task {
                        await syncService.resyncFromServer()
                        resyncing = false
                    }
                }
            } message: {
                Text("Any changes on this iPad that never synced will be lost.")
            }
            .confirmationDialog(
                "Stop sharing and reset sync?",
                isPresented: $confirmingReset,
                titleVisibility: .visible
            ) {
                Button("Stop Sharing & Reset", role: .destructive) {
                    syncService.disable()
                    shareCoordinator.reset()
                }
            } message: {
                Text("All data stays on this iPad. Participants lose access until you share again and send new invitations.")
            }
            .sheet(isPresented: $presentingShareSheet) {
                if let share = shareCoordinator.share {
                    CloudSharingControllerRepresentable(
                        share: share,
                        container: SyncConstants.container,
                        onStopSharing: { syncService.disable() }
                    )
                    .ignoresSafeArea()
                }
            }
        }
    }

    private var soloSection: some View {
        Group {
            Section {
                Button {
                    adopt()
                } label: {
                    if adopting {
                        ProgressView()
                    } else {
                        Label("Download My Ward from iCloud", systemImage: "icloud.and.arrow.down")
                    }
                }
                .disabled(adopting || busy)
            } header: {
                Text("Another of My Devices")
            } footer: {
                Text("Already set this ward up on another iPad or iPhone signed in to the same Apple Account? This pulls it down here — no import, and it doesn't change anyone's invitation.")
            }

            Section {
                Button {
                    enableSharing()
                } label: {
                    if busy {
                        ProgressView()
                    } else {
                        Label("Start Sharing This Ward…", systemImage: "person.badge.plus")
                    }
                }
                .disabled(adopting || busy)
            } header: {
                Text("Share with the Bishopric")
            } footer: {
                Text("For the device that already holds the ward. Its data is uploaded to your iCloud and stays there. You invite up to 4 others; they can work candidates and callings, while importing and the final Announced/Sustained steps stay with you.\n\nIf someone shared a ward with you, open the invitation link they sent — this screen isn't needed.")
            }
        }
    }

    private var ownerSection: some View {
        Section {
            LabeledContent("Role", value: "Owner")
            LabeledContent("Environment", value: Self.environmentLabel)
            LabeledContent("Sync") {
                syncStatusLabel
            }
            if syncService.pendingChangeCount > 0 {
                LabeledContent("Waiting to upload", value: "\(syncService.pendingChangeCount) changes")
            }
            Button {
                presentShareSheet()
            } label: {
                Label("Invite & Manage People…", systemImage: "person.2")
            }
            NavigationLink {
                InviteGuideView()
            } label: {
                Label("Adding a Bishopric Member…", systemImage: "questionmark.circle")
            }
            Button {
                Task { await syncService.fetchNow() }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            Button(role: .destructive) {
                confirmingReset = true
            } label: {
                Label("Stop Sharing & Reset…", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("Shared Ward")
        } footer: {
            Text("Resetting keeps all data on this iPad and returns to not-shared. Use it to start sharing over (participants will need a new invitation).")
        }
    }

    /// Xcode builds use CloudKit's Development environment; TestFlight and
    /// App Store builds use Production. Data does NOT cross environments —
    /// sharing must be started from the same kind of build participants use.
    static var environmentLabel: String {
        #if DEBUG
        "Development (Xcode build)"
        #else
        "Production"
        #endif
    }

    private var participantSection: some View {
        Section {
            LabeledContent("Role", value: "Participant")
            LabeledContent("Sync") {
                syncStatusLabel
            }
            Button {
                Task { await syncService.fetchNow() }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            Button(role: .destructive) {
                syncService.disable()
            } label: {
                Label("Leave Shared Ward", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } header: {
            Text("Shared Ward")
        } footer: {
            Text("Imports and the final Announced/Sustained steps are done by the ward owner.")
        }
    }

    @ViewBuilder
    private var syncStatusLabel: some View {
        switch syncService.status {
        case .idle: Text("Up to date")
        case .syncing: Text("Syncing…")
        case .error(let message): Text(message).foregroundStyle(.red)
        }
    }

    /// Second device of the owner's own: adopt the ward already in this
    /// iCloud account instead of importing or re-sharing.
    private func adopt() {
        adopting = true
        errorMessage = nil
        Task {
            let status = try? await SyncConstants.container.accountStatus()
            guard status == .available else {
                errorMessage = "Sign in to iCloud in Settings to download your ward."
                adopting = false
                return
            }
            if await !syncService.adoptExistingWard() {
                errorMessage = "No ward found in this Apple Account. Start sharing on the device that already has the ward, then try again here."
            }
            adopting = false
        }
    }

    private func enableSharing() {
        busy = true
        errorMessage = nil
        Task {
            do {
                let status = try await SyncConstants.container.accountStatus()
                guard status == .available else {
                    errorMessage = "Sign in to iCloud in Settings to share."
                    busy = false
                    return
                }
                syncService.enableAsOwner()
                _ = try await shareCoordinator.ensureShare(wardName: store.data.wardName)
                presentingShareSheet = true
            } catch {
                errorMessage = "Couldn't start sharing: \(error.localizedDescription)"
            }
            busy = false
        }
    }

    private func presentShareSheet() {
        Task {
            _ = try? await shareCoordinator.ensureShare(wardName: store.data.wardName)
            presentingShareSheet = true
        }
    }
}

/// Diagnostic view of sync activity, copyable for troubleshooting.
struct SyncLogView: View {
    private let log = SyncLog.shared
    @State private var copied = false

    var body: some View {
        List(log.entries.reversed()) { entry in
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.date.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.message)
                    .font(.caption.monospaced())
            }
        }
        .navigationTitle("Sync Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                UIPasteboard.general.string = SyncLog.shared.fullText
                copied = true
            } label: {
                Label("Copy All", systemImage: "doc.on.doc")
            }
        }
        .alert("Log Copied", isPresented: $copied) {
            Button("OK") {}
        }
        .overlay {
            if log.entries.isEmpty {
                ContentUnavailableView(
                    "No Sync Activity Yet",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Make a change on this iPad or another one, then check back.")
                )
            }
        }
    }
}

/// UICloudSharingController wrapper: invitation + participant management.
struct CloudSharingControllerRepresentable: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var onStopSharing: () -> Void = {}

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudSharingControllerRepresentable
        init(parent: CloudSharingControllerRepresentable) { self.parent = parent }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.share[CKShare.SystemFieldKey.title] as? String ?? "Ward Callings"
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onStopSharing()
        }
    }
}
