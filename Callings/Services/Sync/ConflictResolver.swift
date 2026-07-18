import CloudKit
import Foundation

/// Three-way merge for CloudKit save conflicts (`serverRecordChanged`).
///
/// Starts from the server record (which carries the valid change tag) and
/// overlays only the fields the local user actually changed relative to the
/// common ancestor. Special rules:
/// - `candidateIDs` merges as a set relative to the ancestor, so two people
///   adding different candidates offline both win.
/// - `isArchived` is a one-way latch: once the server archived an entry
///   (import or completion), its archive/snapshot/slot fields are
///   authoritative.
enum ConflictResolver {

    /// Returns the merged record to re-save (built on the server record).
    static func merge(client: CKRecord, server: CKRecord, ancestor: CKRecord?) -> CKRecord {
        let merged = server

        let serverArchived = (server["isArchived"] as? Int ?? 0) == 1
        let archiveLatchedKeys: Set<String> = serverArchived
            ? ["isArchived", "archivedAt", "slotID", "releaseStatus", "callStatus",
               "memberToBeCalledID", "snapshotCallingName", "snapshotOrganization",
               "snapshotPreviousHolder", "snapshotNewHolder"]
            : []

        for key in client.allKeys() {
            if archiveLatchedKeys.contains(key) { continue }

            if key == "candidateIDs" {
                merged[key] = mergeCandidateIDs(
                    client: client[key] as? [String] ?? [],
                    server: server[key] as? [String] ?? [],
                    ancestor: ancestor?[key] as? [String] ?? []
                )
                continue
            }

            let clientValue = client[key]
            let ancestorValue = ancestor?[key]
            if !valuesEqual(clientValue, ancestorValue) {
                // The local user changed this field — their change wins.
                merged[key] = clientValue
            }
        }
        return merged
    }

    /// server ∪ clientAdded − clientRemoved (relative to ancestor), keeping
    /// server order and appending client additions.
    static func mergeCandidateIDs(client: [String], server: [String], ancestor: [String]) -> [String] {
        let clientSet = Set(client)
        let ancestorSet = Set(ancestor)
        let added = client.filter { !ancestorSet.contains($0) }
        let removed = ancestorSet.subtracting(clientSet)

        var result = server.filter { !removed.contains($0) }
        for id in added where !result.contains(id) {
            result.append(id)
        }
        return result
    }

    private static func valuesEqual(_ a: CKRecordValue?, _ b: CKRecordValue?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (let a?, let b?): return (a as? NSObject)?.isEqual(b) ?? false
        default: return false
        }
    }
}
