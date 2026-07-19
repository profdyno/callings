import CloudKit
import Foundation
import Observation

/// Owns the CKSyncEngine and connects it to the WardStore:
/// - outbound: diffs store snapshots against a baseline and enqueues record
///   changes (debounced, coalescing bursts of edits)
/// - inbound: applies fetched records/deletions to the store on the main
///   actor, then runs the import reconcile pass
/// - conflicts: three-way merge via ConflictResolver, then re-save
///
/// One engine per device: owner syncs the private database (where WardZone
/// lives), participants sync the shared database. Never started in tests or
/// solo mode.
@Observable
@MainActor
final class SyncService {

    enum Status: Equatable {
        case idle
        case syncing
        case error(String)
    }

    private(set) var status: Status = .idle
    private(set) var pendingChangeCount = 0
    var role: SyncRole { stateStore.settings.role }
    var isOwner: Bool { role == .owner || role == .solo }

    private let store: WardStore
    let stateStore: SyncStateStore
    private var engine: CKSyncEngine?
    private var diffTask: Task<Void, Never>?

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: SyncConstants.zoneName,
            ownerName: stateStore.settings.zoneOwnerName ?? CKCurrentUserDefaultName
        )
    }

    init(store: WardStore, stateStore: SyncStateStore = SyncStateStore()) {
        self.store = store
        self.stateStore = stateStore
        store.syncObserver = { [weak self] _ in
            self?.scheduleDiff()
        }
    }

    // MARK: - Lifecycle

    /// Starts the engine for the persisted role. No-op in solo mode.
    func startIfEnabled() {
        guard engine == nil, role != .solo else { return }
        let database = role == .owner
            ? SyncConstants.container.privateCloudDatabase
            : SyncConstants.container.sharedCloudDatabase

        var stateSerialization: CKSyncEngine.State.Serialization?
        if let data = stateStore.engineStateData {
            stateSerialization = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
    }

    func stop() {
        engine = nil
        diffTask?.cancel()
    }

    /// Owner enable: create the zone, set the baseline to empty so the diff
    /// enqueues every existing record, and start the engine.
    func enableAsOwner() {
        stateStore.settings.role = .owner
        stateStore.settings.zoneOwnerName = nil
        startIfEnabled()
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        stateStore.baseline = WardData()
        scheduleDiff(immediate: true)
    }

    /// Participant enable, after accepting a share into `zoneOwnerName`'s zone.
    func enableAsParticipant(zoneOwnerName: String) {
        stateStore.settings.role = .participant
        stateStore.settings.zoneOwnerName = zoneOwnerName
        // Participant starts from the shared truth.
        store.applyRemote { $0 = WardData() }
        stateStore.baseline = WardData()
        startIfEnabled()
        Task { try? await engine?.fetchChanges() }
    }

    /// Leave/stop: back to solo with local data intact.
    func disable() {
        stop()
        stateStore.reset()
    }

    /// Discards ALL local data and sync state (keeping the role) so a fresh
    /// engine re-downloads the entire ward from iCloud. Recovery tool for a
    /// device whose local state has drifted; unsynced local changes are lost
    /// by design.
    func resyncFromServer() async {
        guard stateStore.settings.role != .solo else { return }
        prepareForResync()
        startIfEnabled()
        await fetchNow()
    }

    /// The synchronous part of a full resync, separated for testability:
    /// stops the engine and wipes data, baseline, engine state, and record
    /// system fields — everything except the sync settings.
    func prepareForResync() {
        diffTask?.cancel()
        stop()
        let settings = stateStore.settings
        stateStore.reset()
        stateStore.settings = settings
        stateStore.baseline = WardData()
        store.applyRemote { $0 = WardData() }
    }

    func fetchNow() async {
        try? await engine?.fetchChanges()
    }

    // MARK: - Permission gating (transition-level)

    /// Participants can move the early ladder steps; only the owner performs
    /// the sacrament-meeting finalizers.
    func canSet(releaseStatus: ReleaseStatus) -> Bool {
        isOwner || releaseStatus != .announced
    }

    func canSet(callStatus: CallStatus) -> Bool {
        isOwner || callStatus != .sustained
    }

    var canImport: Bool { isOwner }

    /// Deleting a calling change discards workflow history — owner only.
    var canDeleteOpenCallings: Bool { isOwner }

    // MARK: - Outbound

    private func scheduleDiff(immediate: Bool = false) {
        guard engine != nil else { return }
        diffTask?.cancel()
        diffTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
            }
            // Always diff the LIVE store state: a snapshot captured at
            // schedule time could be older than remote changes applied since,
            // and enqueueing from it would revert them.
            guard let self else { return }
            self.enqueueDiff(current: self.store.data)
        }
    }

    private func enqueueDiff(current: WardData) {
        guard let engine else { return }
        let baseline = stateStore.baseline ?? WardData()
        let changes = SnapshotDiffer.diff(baseline: baseline, current: current)
        guard !changes.isEmpty else { return }

        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for name in changes.savedRecordNames {
            pending.append(.saveRecord(CKRecord.ID(recordName: name, zoneID: zoneID)))
        }
        for name in changes.deletedRecordNames {
            pending.append(.deleteRecord(CKRecord.ID(recordName: name, zoneID: zoneID)))
            stateStore.removeSystemFields(recordName: name)
        }
        engine.state.add(pendingRecordZoneChanges: pending)
        SyncLog.shared.log("enqueue: save=\(changes.savedRecordNames.joined(separator: ",")) delete=\(changes.deletedRecordNames.joined(separator: ","))")
        stateStore.baseline = current
        pendingChangeCount = engine.state.pendingRecordZoneChanges.count
    }

    /// On launch: recover any drift between the persisted baseline and the
    /// data (mutations made after the last diff before a crash/kill).
    func recoverPendingChangesOnLaunch() {
        guard engine != nil else { return }
        enqueueDiff(current: store.data)
    }

    // MARK: - Record building

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        let name = recordID.recordName
        guard let parsed = CKRecordMapper.parse(recordName: name) else { return nil }

        let record = stateStore.archivedRecord(recordName: name)
            ?? CKRecord(recordType: parsed.type, recordID: recordID)

        switch parsed.type {
        case CKRecordMapper.RecordType.member:
            guard let model = store.data.members.first(where: { $0.id == parsed.id }) else { return nil }
            CKRecordMapper.populate(record, from: model)
        case CKRecordMapper.RecordType.callingDefinition:
            guard let model = store.data.callingDefinitions.first(where: { $0.id == parsed.id }) else { return nil }
            CKRecordMapper.populate(record, from: model)
        case CKRecordMapper.RecordType.callingSlot:
            guard let model = store.data.callingSlots.first(where: { $0.id == parsed.id }) else { return nil }
            CKRecordMapper.populate(record, from: model)
        case CKRecordMapper.RecordType.openCalling:
            guard let model = store.data.openCallings.first(where: { $0.id == parsed.id }) else { return nil }
            CKRecordMapper.populate(record, from: model)
        case CKRecordMapper.RecordType.wardMeta:
            CKRecordMapper.populate(record, from: SnapshotDiffer.meta(of: store.data))
        default:
            return nil
        }
        return record
    }

    // MARK: - Inbound

    /// Applies fetched records/deletions to the store AND, identically, to
    /// the diff baseline. The baseline must advance by exactly the remote
    /// changes — fast-forwarding it to the full store state would swallow
    /// any local edits that haven't been enqueued yet.
    func apply(modifications: [CKRecord], deletions: [CKRecord.ID]) {
        var sawImportGenerationChange = false
        let previousGeneration = store.data.importGeneration

        for record in modifications {
            stateStore.archiveSystemFields(of: record)
        }
        for recordID in deletions {
            stateStore.removeSystemFields(recordName: recordID.recordName)
        }

        store.applyRemote { data in
            Self.integrate(modifications: modifications, deletions: deletions, into: &data)
            if data.importGeneration != previousGeneration {
                sawImportGenerationChange = true
            }
        }
        var baseline = stateStore.baseline ?? WardData()
        Self.integrate(modifications: modifications, deletions: deletions, into: &baseline)
        stateStore.baseline = baseline

        if sawImportGenerationChange {
            reconcileAfterRemoteImport()
        }
    }

    static func integrate(modifications: [CKRecord], deletions: [CKRecord.ID], into data: inout WardData) {
        for record in modifications {
            switch record.recordType {
            case CKRecordMapper.RecordType.member:
                if let model = CKRecordMapper.member(from: record) {
                    upsert(model, into: &data.members)
                }
            case CKRecordMapper.RecordType.callingDefinition:
                if let model = CKRecordMapper.callingDefinition(from: record) {
                    upsert(model, into: &data.callingDefinitions)
                }
            case CKRecordMapper.RecordType.callingSlot:
                if let model = CKRecordMapper.callingSlot(from: record) {
                    upsert(model, into: &data.callingSlots)
                }
            case CKRecordMapper.RecordType.openCalling:
                if let model = CKRecordMapper.openCalling(from: record) {
                    upsert(model, into: &data.openCallings)
                }
            case CKRecordMapper.RecordType.wardMeta:
                let meta = CKRecordMapper.wardMeta(from: record)
                data.wardName = meta.wardName
                data.lastCallingsImport = meta.lastCallingsImport
                data.lastRosterImport = meta.lastRosterImport
                data.importGeneration = meta.importGeneration
            default:
                break
            }
        }
        for recordID in deletions {
            guard let parsed = CKRecordMapper.parse(recordName: recordID.recordName), let id = parsed.id else { continue }
            switch parsed.type {
            case CKRecordMapper.RecordType.member: data.members.removeAll { $0.id == id }
            case CKRecordMapper.RecordType.callingDefinition: data.callingDefinitions.removeAll { $0.id == id }
            case CKRecordMapper.RecordType.callingSlot: data.callingSlots.removeAll { $0.id == id }
            case CKRecordMapper.RecordType.openCalling: data.openCallings.removeAll { $0.id == id }
            default: break
            }
        }
    }

    /// After a remote import replaced the slots: any active local entry whose
    /// slot no longer exists refers to a calling the import removed — archive
    /// it, matching ImportReconciler semantics.
    func reconcileAfterRemoteImport() {
        let slotIDs = Set(store.data.callingSlots.map(\.id))
        let dangling = store.data.openCallings.filter { !$0.isArchived && !slotIDs.contains($0.slotID) }
        guard !dangling.isEmpty else { return }
        let archivedAt = Date()
        func archive(in data: inout WardData) {
            for entry in dangling {
                guard let index = data.openCallings.firstIndex(where: { $0.id == entry.id }) else { continue }
                data.openCallings[index].isArchived = true
                data.openCallings[index].archivedAt = archivedAt
            }
        }
        store.applyRemote { archive(in: &$0) }
        // Mirror only this change into the baseline — never fast-forward it,
        // or unsent local edits would be swallowed.
        var baseline = stateStore.baseline ?? WardData()
        archive(in: &baseline)
        stateStore.baseline = baseline
    }

    private static func upsert<T: Identifiable>(_ model: T, into array: inout [T]) {
        if let index = array.firstIndex(where: { $0.id == model.id }) {
            array[index] = model
        } else {
            array.append(model)
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension SyncService: CKSyncEngineDelegate {

    nonisolated func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await handle(event, syncEngine: syncEngine)
    }

    private func handle(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            stateStore.engineStateData = try? JSONEncoder().encode(stateUpdate.stateSerialization)

        case .accountChange(let accountChange):
            switch accountChange.changeType {
            case .signOut, .switchAccounts:
                stop()
                status = .error("iCloud account changed — sync paused")
            default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            // Zone deleted = share revoked or owner stopped sharing.
            for deletion in changes.deletions where deletion.zoneID.zoneName == SyncConstants.zoneName {
                if role == .participant {
                    stop()
                    stateStore.reset()
                    status = .error("The ward share was ended. This iPad now has a local copy only.")
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            SyncLog.shared.log("fetched: mods=\(changes.modifications.map(\.record.recordID.recordName).joined(separator: ",")) dels=\(changes.deletions.count)")
            apply(
                modifications: changes.modifications.map(\.record),
                deletions: changes.deletions.map(\.recordID)
            )

        case .sentRecordZoneChanges(let sent):
            SyncLog.shared.log("sent: ok=\(sent.savedRecords.map(\.recordID.recordName).joined(separator: ",")) failed=\(sent.failedRecordSaves.count) deleted=\(sent.deletedRecordIDs.count)")
            for save in sent.savedRecords {
                stateStore.archiveSystemFields(of: save)
            }
            for failure in sent.failedRecordSaves {
                SyncLog.shared.log("sendFail: \(failure.record.recordID.recordName) code=\(failure.error.code.rawValue) \(failure.error.localizedDescription)")
                handleSaveFailure(failure, syncEngine: syncEngine)
            }
            pendingChangeCount = syncEngine.state.pendingRecordZoneChanges.count

        case .willFetchChanges, .willSendChanges:
            status = .syncing

        case .didFetchChanges, .didSendChanges:
            status = .idle
            pendingChangeCount = syncEngine.state.pendingRecordZoneChanges.count

        default:
            break
        }
    }

    private func handleSaveFailure(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave, syncEngine: CKSyncEngine) {
        let record = failure.record
        switch failure.error.code {
        case .serverRecordChanged:
            guard let server = failure.error.serverRecord else { return }
            let ancestor = failure.error.ancestorRecord
            let merged = ConflictResolver.merge(client: record, server: server, ancestor: ancestor)
            SyncLog.shared.log("conflict-merged: \(record.recordID.recordName) ancestor=\(ancestor != nil)")
            stateStore.archiveSystemFields(of: merged)
            // Apply the merged truth locally, then re-save it.
            apply(modifications: [merged], deletions: [])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])

        case .zoneNotFound where role == .owner:
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])

        case .unknownItem:
            // Deleted remotely; drop our save and remove locally on next fetch.
            stateStore.removeSystemFields(recordName: record.recordID.recordName)

        default:
            break  // transient errors: the engine retries
        }
    }

    nonisolated func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        SyncLog.shared.post("batch: pending=\(pending.count)")
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            if let record = await self.record(for: recordID) {
                return record
            }
            // Model no longer exists locally — drop the stale pending save.
            SyncLog.shared.post("provider-miss: \(recordID.recordName)")
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            return nil
        }
    }
}
