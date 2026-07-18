import UIKit
import CloudKit

/// UIKit scaffolding required for CloudKit share acceptance: SwiftUI apps
/// receive share metadata through the scene delegate.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Cold launch from tapping a share invitation.
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareAcceptance.receive(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareAcceptance.receive(metadata)
    }
}

/// Hands share metadata from the UIKit delegates to whoever is listening
/// (the sharing coordinator), buffering one metadata for cold launches where
/// the listener isn't up yet.
enum ShareAcceptance {
    static let notification = Notification.Name("CallingsDidReceiveShareMetadata")
    private(set) static var pending: CKShare.Metadata?

    static func receive(_ metadata: CKShare.Metadata) {
        pending = metadata
        NotificationCenter.default.post(name: notification, object: metadata)
    }

    static func consumePending() -> CKShare.Metadata? {
        defer { pending = nil }
        return pending
    }
}
