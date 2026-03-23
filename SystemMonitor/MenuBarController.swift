import AppKit
import SwiftUI

class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stats = SystemStats()

    init() {
        setupStatusItem()
        setupMenu()
    }

    private func setupStatusItem() {
        statusItem.button?.image = NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "System Monitor")
        statusItem.button?.imageScaling = .scaleProportionallyDown
    }

    private func setupMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "System Monitor", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Embedded SwiftUI gauges
        let gaugeView = GaugePanel(stats: stats)
        let hostingView = NSHostingView(rootView: gaugeView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 200)

        let gaugeItem = NSMenuItem()
        gaugeItem.view = hostingView
        menu.addItem(gaugeItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }
}
