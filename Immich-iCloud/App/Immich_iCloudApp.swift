import SwiftUI

@main
struct Immich_iCloudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()
    @State private var showHelpGuide = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .sheet(isPresented: showOnboarding) {
                    OnboardingView()
                        .environment(appState)
                        .interactiveDismissDisabled()
                }
                .sheet(isPresented: $showHelpGuide) {
                    HelpGuideView()
                }
                .task {
                    // Start scheduler if auto-sync is enabled
                    if appState.config.autoSyncEnabled {
                        let scheduler = SyncScheduler(appState: appState)
                        appState.syncScheduler = scheduler
                        scheduler.start()
                    }

                    // Setup menu bar
                    let menuBar = MenuBarController(appState: appState)
                    appState.menuBarController = menuBar
                    menuBar.setup()

                    // Setup Sparkle auto-updater
                    let updater = SparkleUpdater()
                    appState.sparkleUpdater = updater
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            AppCommands(appState: appState, showHelpGuide: $showHelpGuide)
        }
    }

    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !appState.config.onboardingComplete },
            set: { newValue in
                if !newValue {
                    appState.config.onboardingComplete = true
                }
            }
        )
    }
}
