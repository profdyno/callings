import CryptoKit
import Foundation

/// Deterministic UUIDs derived from content, so the same real-world thing
/// gets the same id — and therefore the same CloudKit record name — on every
/// device and on every import.
///
/// Imported callings used to get a fresh `UUID()` on each import. Because the
/// record name is derived from the id, two imports of the same report produced
/// two disjoint record sets; `SyncService.integrate` upserts by id, so it had
/// no way to tell they were the same seats and unioned them instead. That is
/// what duplicated the ward board. Content-derived ids make the union a no-op.
enum StableID {

    /// RFC 4122 §4.3-style name-based UUID (v5 shape, SHA-256 truncated to
    /// 16 bytes) for `namespace` + `key`.
    static func uuid(namespace: String, key: String) -> UUID {
        var digest = Array(SHA256.hash(data: Data("\(namespace)\u{1}\(key)".utf8)).prefix(16))
        digest[6] = (digest[6] & 0x0F) | 0x50  // version 5
        digest[8] = (digest[8] & 0x3F) | 0x80  // RFC 4122 variant
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    /// A calling definition is identified by its LCR import key
    /// (organization | subgroup | name).
    static func definitionID(importKey: String) -> UUID {
        uuid(namespace: "CallingDefinition", key: importKey)
    }

    /// A seat is identified by its definition plus its position among that
    /// definition's rows in the export — so the 2nd "Nursery Leader" seat is
    /// the same record everywhere, whoever happens to hold it.
    static func slotID(definitionID: UUID, seat: Int) -> UUID {
        uuid(namespace: "CallingSlot", key: "\(definitionID.uuidString)|\(seat)")
    }
}
