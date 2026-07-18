import SwiftUI

@main
struct CallingsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: WardStore
    @State private var syncService: SyncService
    @State private var shareCoordinator: ShareCoordinator

    init() {
        let store = WardStore()
        let syncService = SyncService(store: store)
        _store = State(initialValue: store)
        _syncService = State(initialValue: syncService)
        _shareCoordinator = State(initialValue: ShareCoordinator(syncService: syncService))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(syncService)
                .environment(shareCoordinator)
                .task {
                    // Never touch CloudKit under tests or in solo mode.
                    guard NSClassFromString("XCTestCase") == nil else { return }
                    syncService.startIfEnabled()
                    syncService.recoverPendingChangesOnLaunch()
                    await shareCoordinator.acceptPendingIfAny()
                }
        }
    }
}
