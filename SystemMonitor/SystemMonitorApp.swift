import SwiftUI

@main
struct SystemMonitorApp: App {
    @StateObject private var stats = SystemStats()

    var body: some Scene {
        MenuBarExtra {
            MonitorPanel(stats: stats)
        } label: {
            Image(systemName: "gauge.medium")
        }
        .menuBarExtraStyle(.window)
    }
}
