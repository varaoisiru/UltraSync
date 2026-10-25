import SwiftUI

/// Root tab shell: News / Weather / Solar / Space / Hue / Settings,
/// skinned by the active theme with the optional scanline overlay.
/// The News tab carries the unread badge, like the GUI's status bar.
/// On the iOS 26 SDK the tab bar is Liquid Glass natively; it also
/// minimizes away on scroll-down, and tab changes tap a light haptic.
struct ContentView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selectedTab = 0

    private var unreadCount: Int {
        store.newsState.value?.totalUnread ?? 0
    }

    var body: some View {
        let theme = themeManager.theme
        ZStack {
            theme.backdropView.ignoresSafeArea()
            TabView(selection: $selectedTab) {
                NewsView()
                    .tabItem { Label("News", systemImage: "newspaper") }
                    .badge(unreadCount > 0 ? unreadCount : 0)
                    .tag(0)
                WeatherView()
                    .tabItem { Label("Weather", systemImage: "thermometer.sun") }
                    .tag(1)
                SolarView()
                    .tabItem { Label("Solar", systemImage: "sun.max") }
                    .tag(2)
                SpaceView()
                    .tabItem { Label("Space", systemImage: "moon.stars") }
                    .tag(3)
                HueView()
                    .tabItem { Label("Hue", systemImage: "lightbulb") }
                    .tag(4)
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(5)
            }
            .tint(theme.accent1Color)
            .tabBarMinimizeBehavior(.onScrollDown)
            .sensoryFeedback(.impact(weight: .light), trigger: selectedTab)
            if store.showScanlines {
                ScanlinesView()
            }
        }
        .task {
            await store.boot()
        }
    }
}
