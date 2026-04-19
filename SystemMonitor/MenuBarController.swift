import AppKit
import SwiftUI
import Combine
import SystemMonitorCore

class MenuBarController {
    private let statusItem   = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let stats        = SystemStats()
    private let panelState   = PanelState()
    private var menu:        NSMenu?
    private var detailHV:    NSHostingView<DetailView>?
    private var detailItem:  NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    // Layout constants matching SwiftUI's rendering
    private let rowH:       CGFloat = 17   // StatRow / ProcessRow (.body font)
    private let rowGap:     CGFloat = 8    // VStack spacing between rows
    private let coreRowH:   CGFloat = 11   // CoreGrid row (9pt font)
    private let coreRowGap: CGFloat = 5    // LazyVGrid spacing
    private let overhead:   CGFloat = 19   // Divider(1) + topPad(8) + bottomPad(10)

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
        self.menu = menu

        let header = NSMenuItem(title: "System Monitor", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)        // index 0
        menu.addItem(.separator())  // index 1

        let dialsHV = NSHostingView(rootView: DialsView(stats: stats, state: panelState))
        dialsHV.frame = NSRect(x: 0, y: 0, width: 280, height: 145)
        let dialsItem = NSMenuItem()
        dialsItem.view = dialsHV
        menu.addItem(dialsItem)     // index 2

        menu.addItem(.separator())  // index 3 → shifts to 4 when detail inserted
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let dhv = NSHostingView(rootView: DetailView(stats: stats, state: panelState))
        dhv.frame = NSRect(x: 0, y: 0, width: 280, height: 1)
        detailHV = dhv
        let ditem = NSMenuItem()
        ditem.view = dhv
        detailItem = ditem

        // Insert/remove detail when section changes
        panelState.$expanded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] section in
                guard let self, let menu = self.menu,
                      let ditem = self.detailItem, let dhv = self.detailHV else { return }
                let inMenu = menu.index(of: ditem) >= 0
                if let section, !inMenu {
                    dhv.frame.size.height = self.height(for: section)
                    menu.insertItem(ditem, at: 3)
                } else if section == nil, inMenu {
                    menu.removeItem(ditem)
                }
            }
            .store(in: &cancellables)

        // Re-size when content changes while a section is open (e.g. CPU sampling → loaded)
        stats.$perCoreCPU.combineLatest(stats.$topCPUProcesses, stats.$topMemProcesses, stats.$largeFiles)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateDetailHeight() }
            .store(in: &cancellables)

        statusItem.menu = menu
    }

    // Exact height for each section based on known row counts
    private func height(for section: PanelSection) -> CGFloat {
        switch section {

        case .cpu:
            guard !stats.perCoreCPU.isEmpty else {
                return overhead + rowH   // "Sampling cores…" placeholder
            }
            let gridRows  = (stats.perCoreCPU.count + 1) / 2
            let gridH     = CGFloat(gridRows) * coreRowH + CGFloat(gridRows - 1) * coreRowGap
            var inner     = gridH + rowGap + rowH   // grid + gap + load-avg row
            let nProcs    = stats.topCPUProcesses.count
            if nProcs > 0 {
                inner += rowGap + 1 + rowGap   // gap + divider + gap
                inner += CGFloat(nProcs) * rowH + CGFloat(nProcs - 1) * rowGap
            }
            return overhead + inner

        case .mem:
            let n = max(stats.topMemProcesses.count, 1)
            return overhead + CGFloat(n) * rowH + CGFloat(n - 1) * rowGap

        case .disk:
            guard !stats.largeFiles.isEmpty else {
                return overhead + rowH   // "Scanning…" placeholder
            }
            let n = stats.largeFiles.count
            return overhead + CGFloat(n) * rowH + CGFloat(n - 1) * rowGap
        }
    }

    private func updateDetailHeight() {
        guard let section = panelState.expanded,
              let menu, let ditem = detailItem, let dhv = detailHV else { return }
        guard menu.index(of: ditem) >= 0 else { return }
        let h = height(for: section)
        guard abs(dhv.frame.size.height - h) > 2 else { return }
        dhv.frame.size.height = h
        menu.removeItem(ditem)
        menu.insertItem(ditem, at: 3)
    }
}
