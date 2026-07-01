import Foundation

struct APIError: Decodable {
    let error: String
}

struct SystemStatus: Decodable {
    let tunnel: Tunnel
    let ipForwarding: Bool
    let nat: String?
    let publicIp: String?
    let daemons: Daemons
    let healthCheck: HealthCheck?
}

struct Tunnel: Decodable {
    let up: Bool
    let iface: String?
    let listenPort: String?
    let publicKey: String?
}

struct Daemons: Decodable {
    let wireguard: Bool
    let duckdns: Bool
    let health: Bool
}

struct HealthCheck: Decodable {
    let active: Bool
    let lastFix: LastFix?
}

struct LastFix: Decodable {
    let timestamp: String
    let message: String
}

struct PeerListResponse: Decodable {
    let peers: [Peer]
}

struct Peer: Decodable, Identifiable {
    let publicKey: String
    let endpoint: String?
    let allowedIps: String?
    let latestHandshake: String?
    let rx: String?
    let tx: String?
    let online: Bool?
    let name: String?

    var id: String { publicKey }
}

struct ClientListResponse: Decodable {
    let clients: [VPNClient]
}

struct VPNClient: Decodable, Identifiable {
    let name: String
    let publicKey: String?
    let allowedIps: String?

    var id: String { name }
}

struct AuthResponse: Decodable {
    let authenticated: Bool
}

struct GenericSuccess: Decodable {
    let success: Bool?
    let message: String?
}

struct ClientQRResponse: Decodable {
    let qrDataUrl: String
}
