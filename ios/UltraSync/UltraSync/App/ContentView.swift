import SwiftUI

/// Root tab shell: News / Weather / Solar / Space / Hue / Settings,
/// skinned by the active theme with the optional scanline overlay.
/// The News tab carries the unread badge, like the GUI's status bar.
struct ContentView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeManager: ThemeManager

    private var unreadCount: Int {
        store.newsState.value?.totalUnread ?? 0
    }

    var body: some View {
        let theme = themeManager.theme
        ZStack {
            theme.bgColor.ignoresSafeArea()
            TabView {
                NewsView()
                    .tabItem { Label("News", systemImage: "newspaper") }
                    .badge(unreadCount > 0 ? unreadCount : 0)
                WeatherView()
                    .tabItem { Label("Weather", systemImage: "thermometer.sun") }
                SolarView()
                    .tabItem { Label("Solar", systemImage: "sun.max") }
                SpaceView()
                    .tabItem { Label("Space", systemImage: "moon.stars") }
                HueView()
                    .tabItem { Label("Hue", systemImage: "lightbulb") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .tint(theme.accent1Color)
            if store.showScanlines {
                ScanlinesView()
            }
        }
        .task {
            await store.boot()
        }
    }
}
