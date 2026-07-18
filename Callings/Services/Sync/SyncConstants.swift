import CloudKit

/// CloudKit identifiers. The container ID is fixed (not derived from the
/// bundle ID, which embeds the team ID and is empty in local builds) and is
/// permanent once TestFlight users have data in it.
enum SyncConstants {
    static let containerIdentifier = "iCloud.com.profdyno.callings"
    static let zoneName = "WardZone"

    static var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }
}
