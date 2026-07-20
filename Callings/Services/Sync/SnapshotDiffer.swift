import Foundation

/// Computes the record changes between two WardData snapshots. Pure and fast:
/// all models are small Equatable value structs (~900 records total).
enum SnapshotDiffer {

    struct ChangeSet: Equatable {
        var savedRecordNames: [String] = []
        var deletedRecordNames: [String] = []

        var isEmpty: Bool { savedRecordNames.isEmpty && deletedRecordNames.isEmpty }
    }

    static func diff(baseline: WardData, current: WardData) -> ChangeSet {
        var changes = ChangeSet()

        diffTable(
            baseline: baseline.members, current: current.members,
            recordName: CKRecordMapper.recordName(forMember:), into: &changes
        )
        diffTable(
            baseline: baseline.callingDefinitions, current: current.callingDefinitions,
            recordName: CKRecordMapper.recordName(forDefinition:), into: &changes
        )
        diffTable(
            baseline: baseline.callingSlots, current: current.callingSlots,
            recordName: CKRecordMapper.recordName(forSlot:), into: &changes
        )
        diffTable(
            baseline: baseline.openCallings, current: current.openCallings,
            recordName: CKRecordMapper.recordName(forOpenCalling:), into: &changes
        )

        if meta(of: baseline) != meta(of: current) {
            changes.savedRecordNames.append(CKRecordMapper.wardMetaRecordName)
        }
        return changes
    }

    static func meta(of data: WardData) -> CKRecordMapper.WardMeta {
        CKRecordMapper.WardMeta(
            wardName: data.wardName,
            lastCallingsImport: data.lastCallingsImport,
            lastRosterImport: data.lastRosterImport,
            schemaVersion: data.schemaVersion,
            importGeneration: data.importGeneration,
            customTags: data.customTags
        )
    }

    private static func diffTable<T: Identifiable & Equatable>(
        baseline: [T], current: [T],
        recordName: (T.ID) -> String,
        into changes: inout ChangeSet
    ) {
        let baselineByID = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        var seen = Set<T.ID>()
        for item in current {
            seen.insert(item.id)
            if baselineByID[item.id] != item {
                changes.savedRecordNames.append(recordName(item.id))
            }
        }
        for item in baseline where !seen.contains(item.id) {
            changes.deletedRecordNames.append(recordName(item.id))
        }
    }
}
