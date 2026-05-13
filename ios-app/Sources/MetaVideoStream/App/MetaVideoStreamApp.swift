import SwiftUI
import MWDATCore

class AppDelegate: NSObject, UIApplicationDelegate {
    var wearables: WearablesManager!

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Configure the SDK during the correct phase of the iOS application lifecycle
        do {
            try Wearables.configure()
            wearables = WearablesManager()
        } catch {
            assertionFailure("Wearables SDK configuration failed: \(error)")
        }
        return true
    }
}

@main
struct MetaVideoStreamApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.wearables)
                .onOpenURL { url in
                    // Forward Meta AI app callbacks back into the SDK
                    Task {
                        try? await Wearables.shared.handleUrl(url)
                    }
                }
        }
    }
}
