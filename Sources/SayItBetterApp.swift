import SwiftUI

@main
struct SayItBetterApp: App {
    @StateObject private var store = SessionStore()
    @StateObject private var listener = Listener()
    @StateObject private var coach = Coach()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(listener)
                .environmentObject(coach)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: SessionStore
    @EnvironmentObject private var listener: Listener
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            ListenView()
                .tabItem { Label("Listen", systemImage: "mic") }
            ReviewView()
                .tabItem { Label("Review", systemImage: "text.badge.checkmark") }
        }
        .tint(Theme.go)
        .onAppear {
            let store = self.store
            listener.onPhrase = { [weak store] text in
                store?.append(text)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                listener.appBecameActive()
            } else {
                store.flush()
            }
        }
    }
}
