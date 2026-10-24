import SwiftUI

/// UltraSync for iOS — native SwiftUI fork of the UltraSync 1.0
/// dashboard. Signed with free provisioning (Personal Team); see
/// ios/README-IOS.md.
@main
struct UltraSyncApp: App {
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var store = DataStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
