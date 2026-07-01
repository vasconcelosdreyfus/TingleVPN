import Foundation
import AppKit
import UniformTypeIdentifiers

final class DashboardViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var username = "admin"
    @Published var password = ""

    @Published var status: SystemStatus?
    @Published var peers: [Peer] = []
    @Published var clients: [VPNClient] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient()
    private let backendService = BackendServiceManager()
    private let notifier = NotificationManager()
    private var hasBootstrapped = false
    private var refreshTask: Task<Void, Never>?
    private let foregroundRefreshIntervalNs: UInt64 = 5_000_000_000
    private let backgroundRefreshIntervalNs: UInt64 = 20_000_000_000
    private var isWindowActive = false
    private var knownOnlinePeers = Set<String>()
    private var hasOnlinePeersBaseline = false

    @MainActor
    func bootstrap() async {
        if hasBootstrapped { return }
        hasBootstrapped = true
        await backendService.ensureRunning()
        do {
            isAuthenticated = try await api.me()
            if isAuthenticated {
                await notifier.requestAuthorizationIfNeeded()
                startAutoRefresh()
                await refreshAll()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func login() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await backendService.ensureRunning()
        do {
            try await api.login(username: username, password: password)
            password = ""
            isAuthenticated = true
            await notifier.requestAuthorizationIfNeeded()
            startAutoRefresh()
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func logout() async {
        do {
            try await api.logout()
            stopAutoRefresh()
            isAuthenticated = false
            status = nil
            peers = []
            clients = []
            knownOnlinePeers = []
            hasOnlinePeersBaseline = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func refreshAll() async {
        guard isAuthenticated else { return }
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let s = api.fetchStatus()
            async let p = api.fetchPeers()
            async let c = api.fetchClients()
            status = try await s
            let fetchedPeers = try await p
            await notifyNewlyConnectedPeers(fetchedPeers)
            peers = fetchedPeers
            clients = try await c
        } catch {
            if (error as NSError).code == 401 {
                stopAutoRefresh()
                isAuthenticated = false
                knownOnlinePeers = []
                hasOnlinePeersBaseline = false
            }
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func createClient(name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await api.createClient(name: name)
            clients = try await api.fetchClients()
            peers = try await api.fetchPeers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func removeClient(_ name: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await api.removeClient(name: name)
            clients = try await api.fetchClients()
            peers = try await api.fetchPeers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func renameClient(oldName: String, newName: String) async {
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldName.isEmpty, !newName.isEmpty, oldName != newName else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await api.renameClient(oldName: oldName, newName: newName)
            clients = try await api.fetchClients()
            peers = try await api.fetchPeers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func fetchClientQRImage(_ name: String) async -> NSImage? {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let dataUrl = try await api.fetchClientQRDataURL(name: name)
            guard let data = decodeDataURL(dataUrl) else { return nil }
            return NSImage(data: data)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @MainActor
    func downloadClientConfig(_ name: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let configText = try await api.fetchClientConfigText(name: name)
            try saveConfigToDisk(clientName: name, config: configText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func disconnectPeer(_ key: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await api.disconnectPeer(publicKey: key)
            peers = try await api.fetchPeers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    func setWindowActive(_ active: Bool) {
        if isWindowActive == active { return }
        isWindowActive = active
        if active && isAuthenticated {
            Task { await refreshAll() }
        }
    }

    private func startAutoRefresh() {
        if refreshTask != nil { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let interval = self.currentRefreshIntervalNs()
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                await self.refreshAll()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func currentRefreshIntervalNs() -> UInt64 {
        isWindowActive ? foregroundRefreshIntervalNs : backgroundRefreshIntervalNs
    }

    private func notifyNewlyConnectedPeers(_ fetchedPeers: [Peer]) async {
        let onlineNow = Set(fetchedPeers.filter { $0.online == true }.map { $0.publicKey })

        if hasOnlinePeersBaseline {
            let newlyOnline = onlineNow.subtracting(knownOnlinePeers)
            let newlyOffline = knownOnlinePeers.subtracting(onlineNow)

            for key in newlyOnline {
                if let peer = fetchedPeers.first(where: { $0.publicKey == key }) {
                    await notifier.notifyPeerConnected(displayName: peer.name ?? shortKey(key))
                }
            }
            for key in newlyOffline {
                if let peer = peers.first(where: { $0.publicKey == key }) {
                    await notifier.notifyPeerDisconnected(displayName: peer.name ?? shortKey(key))
                } else {
                    await notifier.notifyPeerDisconnected(displayName: shortKey(key))
                }
            }
        } else {
            hasOnlinePeersBaseline = true
        }

        knownOnlinePeers = onlineNow
    }

    private func shortKey(_ key: String) -> String {
        if key.count <= 14 { return key }
        let start = key.prefix(6)
        let end = key.suffix(6)
        return "\(start)...\(end)"
    }

    private func decodeDataURL(_ dataUrl: String) -> Data? {
        guard let comma = dataUrl.firstIndex(of: ",") else { return nil }
        let base64 = String(dataUrl[dataUrl.index(after: comma)...])
        return Data(base64Encoded: base64)
    }

    private func saveConfigToDisk(clientName: String, config: String) throws {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(clientName).conf"
        panel.title = "Salvar Config do Cliente"
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            try config.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
