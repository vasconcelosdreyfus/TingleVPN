import Foundation

final class APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:3000")!) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    func login(username: String, password: String) async throws {
        let body = ["username": username, "password": password]
        _ = try await request(path: "/api/login", method: "POST", body: body, responseType: AuthResponse.self)
    }

    func logout() async throws {
        _ = try await request(path: "/api/logout", method: "POST", responseType: GenericSuccess.self)
    }

    func me() async throws -> Bool {
        let response = try await request(path: "/api/me", responseType: AuthResponse.self)
        return response.authenticated
    }

    func fetchStatus() async throws -> SystemStatus {
        try await request(path: "/api/status", responseType: SystemStatus.self)
    }

    func fetchPeers() async throws -> [Peer] {
        let response = try await request(path: "/api/peers", responseType: PeerListResponse.self)
        return response.peers
    }

    func fetchClients() async throws -> [VPNClient] {
        let response = try await request(path: "/api/clients", responseType: ClientListResponse.self)
        return response.clients
    }

    func createClient(name: String) async throws {
        let body = ["name": name]
        _ = try await request(path: "/api/clients", method: "POST", body: body, responseType: GenericSuccess.self)
    }

    func removeClient(name: String) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        _ = try await request(path: "/api/clients/\(encoded)", method: "DELETE", responseType: GenericSuccess.self)
    }

    func renameClient(oldName: String, newName: String) async throws {
        let encoded = oldName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? oldName
        let body = ["newName": newName]
        _ = try await request(path: "/api/clients/\(encoded)", method: "PATCH", body: body, responseType: GenericSuccess.self)
    }

    func fetchClientQRDataURL(name: String) async throws -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let response = try await request(path: "/api/clients/\(encoded)/qr", responseType: ClientQRResponse.self)
        return response.qrDataUrl
    }

    func fetchClientConfigText(name: String) async throws -> String {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let data = try await requestRaw(path: "/api/clients/\(encoded)/config")
        return String(decoding: data, as: UTF8.self)
    }

    func disconnectPeer(publicKey: String) async throws {
        let encoded = publicKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? publicKey
        _ = try await request(path: "/api/peers/\(encoded)/disconnect", method: "POST", responseType: GenericSuccess.self)
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        body: [String: String]? = nil,
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NSError(domain: "TingleVPN", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "TingleVPN", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }

        if (200...299).contains(http.statusCode) {
            return try JSONDecoder().decode(T.self, from: data)
        }

        if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
            throw NSError(domain: "TingleVPN", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: apiError.error])
        }

        if http.statusCode == 401 {
            throw NSError(domain: "TingleVPN", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }

        throw NSError(domain: "TingleVPN", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed"])
    }

    private func requestRaw(
        path: String,
        method: String = "GET"
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NSError(domain: "TingleVPN", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "TingleVPN", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        if (200...299).contains(http.statusCode) { return data }
        if http.statusCode == 401 {
            throw NSError(domain: "TingleVPN", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized"])
        }
        throw NSError(domain: "TingleVPN", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed"])
    }
}
