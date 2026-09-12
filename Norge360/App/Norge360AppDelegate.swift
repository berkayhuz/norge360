import Foundation
import UIKit

final class Norge360AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .norge360DidReceiveAPNSToken, object: token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(name: .norge360DidFailAPNSRegistration, object: error)
    }
}

extension Notification.Name {
    static let norge360DidReceiveAPNSToken = Notification.Name("norge360.didReceiveAPNSToken")
    static let norge360DidFailAPNSRegistration = Notification.Name("norge360.didFailAPNSRegistration")
}
