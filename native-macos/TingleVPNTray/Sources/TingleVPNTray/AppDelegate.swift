import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: NSWindowController?
    private let viewModel = DashboardViewModel()
    private let backendManager = BackendServiceManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplicationIcon()
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = loadAppIconImage() {
            item.button?.image = resizedIcon(image, size: 18)
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = "TingleVPN"
        } else {
            item.button?.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "TingleVPN")
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = "TingleVPN"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Abrir painel", action: #selector(openPanel), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Atualizar", action: #selector(refreshData), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())

        let backendSubmenu = NSMenu()
        let startItem = NSMenuItem(title: "Iniciar backend", action: #selector(startBackend), keyEquivalent: "")
        startItem.target = self
        backendSubmenu.addItem(startItem)
        let stopItem = NSMenuItem(title: "Parar backend", action: #selector(stopBackend), keyEquivalent: "")
        stopItem.target = self
        backendSubmenu.addItem(stopItem)
        let restartItem = NSMenuItem(title: "Reiniciar backend", action: #selector(restartBackend), keyEquivalent: "")
        restartItem.target = self
        backendSubmenu.addItem(restartItem)

        let backendMenuItem = NSMenuItem(title: "Backend", action: nil, keyEquivalent: "")
        backendMenuItem.submenu = backendSubmenu
        menu.addItem(backendMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Desinstalar app", action: #selector(uninstallApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(quitApp), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    private func setupApplicationIcon() {
        if let icon = loadAppIconImage() {
            NSApp.applicationIconImage = icon
        }
    }

    private func loadAppIconImage() -> NSImage? {
        if let bundled = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let image = NSImage(contentsOfFile: bundled) {
            return image
        }

        guard let root = findProjectRoot() else { return nil }
        let preferred = root + "/assets/images/tinglevpn.png"
        if let image = NSImage(contentsOfFile: preferred) {
            return image
        }
        let fallback = root + "/dashboard/public/logo.png"
        return NSImage(contentsOfFile: fallback)
    }

    private func resizedIcon(_ image: NSImage, size: CGFloat) -> NSImage {
        let output = NSImage(size: NSSize(width: size, height: size))
        output.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    private func findProjectRoot() -> String? {
        let fm = FileManager.default
        var current = fm.currentDirectoryPath

        for _ in 0..<8 {
            if fm.fileExists(atPath: current + "/assets/images/tinglevpn.png") ||
                fm.fileExists(atPath: current + "/dashboard/public/logo.png") {
                return current
            }
            let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
            if parent == current { break }
            current = parent
        }

        let defaultPath = "/Users/servidor/apps/tinglevpn"
        if fm.fileExists(atPath: defaultPath + "/assets/images/tinglevpn.png") ||
            fm.fileExists(atPath: defaultPath + "/dashboard/public/logo.png") {
            return defaultPath
        }
        return nil
    }

    @objc private func openPanel() {
        if windowController == nil {
            let contentView = ContentView(viewModel: viewModel)
            let hosting = NSHostingController(rootView: contentView)

            let window = NSWindow(contentViewController: hosting)
            window.title = "TingleVPN"
            window.setContentSize(NSSize(width: 1140, height: 700))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.delegate = self

            windowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        viewModel.setWindowActive(true)

        Task { await viewModel.bootstrap() }
    }

    @objc private func refreshData() {
        Task { await viewModel.refreshAll() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @MainActor
    @objc private func startBackend() {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.backendManager.startBackend()
            self.presentBackendResult(result)
            await self.viewModel.refreshAll()
        }
    }

    @MainActor
    @objc private func stopBackend() {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.backendManager.stopBackend()
            self.presentBackendResult(result)
            await self.viewModel.refreshAll()
        }
    }

    @MainActor
    @objc private func restartBackend() {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.backendManager.restartBackend()
            self.presentBackendResult(result)
            await self.viewModel.refreshAll()
        }
    }

    @MainActor
    @objc private func uninstallApp() {
        let result = backendManager.uninstallInstalledApp()
        switch result {
        case .ok(let message):
            showAlert(title: "TingleVPN", message: message)
            NSApp.terminate(nil)
        case .failed(let message):
            showAlert(title: "Desinstalação", message: message)
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        viewModel.setWindowActive(true)
    }

    func windowDidResignKey(_ notification: Notification) {
        viewModel.setWindowActive(false)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.setWindowActive(false)
    }

    @MainActor
    private func presentBackendResult(_ result: BackendServiceManager.BackendActionResult) {
        switch result {
        case .ok(let message):
            showAlert(title: "Backend", message: message)
        case .failed(let message):
            showAlert(title: "Backend", message: message)
        }
    }

    @MainActor
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
