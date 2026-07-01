import Foundation

final class BackendServiceManager {
    enum BackendActionResult {
        case ok(String)
        case failed(String)
    }

    private let baseURL = URL(string: "http://127.0.0.1:3000")!

    func ensureRunning() async {
        if await isReachable() { return }

        tryStartWithManageScript()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if await isReachable() { return }

        tryStartWithNode()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
    }

    func startBackend() async -> BackendActionResult {
        if await isReachable() {
            return .ok("Backend já estava rodando.")
        }

        if runShellSync("cd '\(projectRootOrDefault())' && sudo -n ./manage.sh dashboard start >/dev/null 2>&1") == 0 {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if await isReachable() {
                return .ok("Backend iniciado via manage.sh.")
            }
        }

        tryStartWithNode()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if await isReachable() {
            return .ok("Backend iniciado via node server.js.")
        }
        return .failed("Não foi possível iniciar o backend.")
    }

    func stopBackend() async -> BackendActionResult {
        let root = projectRootOrDefault()
        _ = runShellSync("cd '\(root)' && sudo -n ./manage.sh dashboard stop >/dev/null 2>&1 || true")
        _ = runShellSync("pkill -f '/dashboard/server.js' >/dev/null 2>&1 || true")
        try? await Task.sleep(nanoseconds: 900_000_000)
        if await isReachable() {
            return .failed("Backend ainda está respondendo na porta 3000.")
        }
        return .ok("Backend parado.")
    }

    func restartBackend() async -> BackendActionResult {
        let root = projectRootOrDefault()
        if runShellSync("cd '\(root)' && sudo -n ./manage.sh dashboard restart >/dev/null 2>&1") == 0 {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if await isReachable() {
                return .ok("Backend reiniciado via manage.sh.")
            }
        }

        _ = await stopBackend()
        return await startBackend()
    }

    func uninstallInstalledApp() -> BackendActionResult {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            return .failed("Desinstalação automática só funciona na versão .app instalada.")
        }

        let home = NSHomeDirectory()
        let plist = "\(home)/Library/LaunchAgents/com.tinglevpn.tray.plist"
        _ = runShellSync("launchctl unload '\(plist)' >/dev/null 2>&1 || true")
        _ = runShellSync("rm -f '\(plist)'")
        _ = runShellDetached("sleep 1; rm -rf '\(appPath)'")
        return .ok("Aplicativo desinstalado. O processo será encerrado.")
    }

    private func isReachable() async -> Bool {
        guard let url = URL(string: "/api/me", relativeTo: baseURL) else { return false }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }

    private func tryStartWithManageScript() {
        guard let root = findProjectRoot(), FileManager.default.fileExists(atPath: root + "/manage.sh") else { return }
        let command = "cd '\(root)' && sudo -n ./manage.sh dashboard start >/dev/null 2>&1 || true"
        _ = runShellDetached(command)
    }

    private func tryStartWithNode() {
        guard let root = findProjectRoot() else { return }
        let dashboardPath = root + "/dashboard"
        guard FileManager.default.fileExists(atPath: dashboardPath + "/server.js") else { return }

        let command = "cd '\(dashboardPath)' && nohup node server.js >> /tmp/tinglevpn-dashboard-native.log 2>&1 &"
        _ = runShellDetached(command)
    }

    @discardableResult
    private func runShellDetached(_ command: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return 0
        } catch {
            return 1
        }
    }

    private func runShellSync(_ command: String) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 1
        }
    }

    private func findProjectRoot() -> String? {
        let fm = FileManager.default
        var current = fm.currentDirectoryPath

        for _ in 0..<8 {
            if fm.fileExists(atPath: current + "/manage.sh") && fm.fileExists(atPath: current + "/dashboard/server.js") {
                return current
            }
            let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
            if parent == current { break }
            current = parent
        }

        let defaultPath = "/Users/servidor/apps/tinglevpn"
        if fm.fileExists(atPath: defaultPath + "/manage.sh") && fm.fileExists(atPath: defaultPath + "/dashboard/server.js") {
            return defaultPath
        }
        return nil
    }

    private func projectRootOrDefault() -> String {
        findProjectRoot() ?? "/Users/servidor/apps/tinglevpn"
    }
}
