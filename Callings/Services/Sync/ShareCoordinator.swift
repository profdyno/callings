import CloudKit
import Foundation
import Observation

/// Creates and manages the zone-wide CKShare (owner) and accepts share
/// invitations (participant).
@Observable
@MainActor
final class ShareCoordinator {

    private let syncService: SyncService
    private(set) var share: CKShare?
    private(set) var lastError: String?

    init(syncService: SyncService) {
        self.syncService = syncService
        NotificationCenter.default.addObserver(
            forName: ShareAcceptance.notification, object: nil, queue: .main
        ) { [weak self] note in
            guard let metadata = note.object as? CKShare.Metadata else { return }
            Task { @MainActor in await self?.accept(metadata) }
        }
    }

    /// Owner: fetch the existing share or create a zone-wide one.
    func ensureShare(wardName: String?) async throws -> CKShare {
        if let share { return share }
        let database = SyncConstants.container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: SyncConstants.zoneName, ownerName: CKCurrentUserDefaultName)

        // Zone must exist server-side before it can be shared.
        _ = try await database.save(CKRecordZone(zoneID: zoneID))

        // Reuse an existing share when there is one.
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await database.record(for: shareID) as? CKShare {
            share = existing
            return existing
        }

        let newShare = CKShare(recordZoneID: zoneID)
        newShare[CKShare.SystemFieldKey.title] = (wardName ?? "Ward Callings") as CKRecordValue
        newShare.publicPermission = .none
        let result = try await database.modifyRecords(saving: [newShare], deleting: [])
        for (_, saveResult) in result.saveResults {
            if case .success(let record) = saveResult, let saved = record as? CKShare {
                share = saved
                return saved
            }
        }
        share = newShare
        return newShare
    }

    /// Participant: accept an invitation and switch into shared mode.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await SyncConstants.container.accept(metadata)
            let ownerName = metadata.share.recordID.zoneID.ownerName
            syncService.stateStore.settings.shareRecordName = metadata.share.recordID.recordName
            syncService.enableAsParticipant(zoneOwnerName: ownerName)
            lastError = nil
        } catch {
            lastError = "Couldn't join the shared ward: \(error.localizedDescription)"
        }
    }

    /// Consumes a cold-launch share invitation, if one arrived before we
    /// were listening.
    func acceptPendingIfAny() async {
        if let metadata = ShareAcceptance.consumePending() {
            await accept(metadata)
        }
    }

    /// Drops the cached share (used when sharing is reset so the next
    /// ensureShare creates a fresh one in the current environment).
    func reset() {
        share = nil
    }
}
