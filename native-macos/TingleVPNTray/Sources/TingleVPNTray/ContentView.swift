import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("themeMode") private var themeModeRaw = ThemeMode.system.rawValue
    @State private var showAddClientModal = false
    @State private var addClientName = ""
    @State private var showRenameClientModal = false
    @State private var renameOldName = ""
    @State private var renameNewName = ""
    @State private var showQRModal = false
    @State private var qrClientName = ""
    @State private var qrImage: NSImage?
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 3)

    private var selectedThemeMode: ThemeMode {
        ThemeMode(rawValue: themeModeRaw) ?? .system
    }

    private var activeColorScheme: ColorScheme {
        selectedThemeMode == .system ? systemColorScheme : (selectedThemeMode == .dark ? .dark : .light)
    }

    private var theme: ThemePalette {
        activeColorScheme == .dark ? .dark : .light
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.bgTop, theme.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                if viewModel.isAuthenticated {
                    dashboardBody
                } else {
                    loginBody
                }

                if let error = viewModel.errorMessage {
                    HStack {
                        Text(error)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(theme.danger)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(theme.card)
                    .overlay(
                        Rectangle()
                            .fill(theme.cardBorder)
                            .frame(height: 1),
                        alignment: .top
                    )
                }
            }
        }
        .frame(minWidth: 1080, minHeight: 620)
        .task {
            await viewModel.bootstrap()
        }
        .preferredColorScheme(selectedThemeMode.preferredColorScheme)
        .sheet(isPresented: $showAddClientModal) {
            addClientSheet
        }
        .sheet(isPresented: $showRenameClientModal) {
            renameClientSheet
        }
        .sheet(isPresented: $showQRModal) {
            qrCodeSheet
        }
    }

    private var loginBody: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("TingleVPN")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(theme.text)
                Text("Painel nativo")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.muted)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Usuário", text: $viewModel.username)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.cardAlt)
                    .foregroundColor(theme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                SecureField("Senha", text: $viewModel.password)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.cardAlt)
                    .foregroundColor(theme.text)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button {
                Task { await viewModel.login() }
            } label: {
                HStack {
                    if viewModel.isLoading { ProgressView().controlSize(.small) }
                    Text("Entrar")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(theme.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
        }
        .padding(24)
        .background(theme.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var dashboardBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusSection
                peersSection
                clientsSection
            }
            .padding(20)
        }
    }

    private var statusSection: some View {
        sectionCard(title: "Status do Servidor") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                statusMetric(
                    "TUNNEL",
                    viewModel.status?.tunnel.up == true ? "Ativo" : "Inativo",
                    subtitle: viewModel.status?.tunnel.iface ?? "-",
                    ok: viewModel.status?.tunnel.up == true
                )
                statusMetric(
                    "IP FORWARDING",
                    ipForwardingText(viewModel.status?.ipForwarding),
                    ok: viewModel.status?.ipForwarding == true
                )
                statusMetric("NAT", (viewModel.status?.nat?.isEmpty == false) ? "Ativo" : "Inativo", ok: (viewModel.status?.nat?.isEmpty == false))

                statusMetric("PUBLIC IP", viewModel.status?.publicIp ?? "-", ok: (viewModel.status?.publicIp?.isEmpty == false))
                statusMetric("WG DAEMON", daemonText(viewModel.status?.daemons.wireguard), ok: viewModel.status?.daemons.wireguard == true)
                statusMetric("DUCKDNS", daemonText(viewModel.status?.daemons.duckdns), ok: viewModel.status?.daemons.duckdns == true)

                statusMetric(
                    "HEALTH CHECK",
                    healthText(viewModel.status?.daemons.health),
                    subtitle: healthLastFixText(),
                    ok: viewModel.status?.daemons.health == true
                )
                statusMetric("INTERFACE", viewModel.status?.tunnel.iface ?? "-", ok: viewModel.status?.tunnel.iface != nil)
                statusMetric("PORT", viewModel.status?.tunnel.listenPort ?? "-", ok: viewModel.status?.tunnel.listenPort != nil)
            }
        }
    }

    private var clientsSection: some View {
        sectionCard(title: "Clientes Configurados", trailing: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(viewModel.clients.count) client(s)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(theme.muted)
                    Button {
                        addClientName = ""
                        showAddClientModal = true
                    } label: {
                        Text("+ Adicionar")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.accent)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoading)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                tableHeader(["NOME", "ENDERECO IP", "CHAVE PUBLICA", "ACOES"], widths: [0.19, 0.14, 0.37, 0.30])

                if viewModel.clients.isEmpty {
                    emptyRow("Nenhum cliente cadastrado")
                } else {
                    ForEach(viewModel.clients) { client in
                        HStack(spacing: 0) {
                            tableCell(client.name, width: 0.19, weight: .semibold, color: theme.text, truncation: .tail)
                            tableCell(client.allowedIps ?? "-", width: 0.14, color: theme.muted, truncation: .tail)
                            tableCell(longKey(client.publicKey ?? "-"), width: 0.37, color: theme.muted, truncation: .middle)
                            HStack(spacing: 10) {
                                actionLink("Renomear", color: theme.accent) {
                                    renameOldName = client.name
                                    renameNewName = client.name
                                    showRenameClientModal = true
                                }
                                actionLink("Codigo QR", color: theme.accent) {
                                    qrClientName = client.name
                                    qrImage = nil
                                    showQRModal = true
                                    Task { qrImage = await viewModel.fetchClientQRImage(client.name) }
                                }
                                actionLink("Baixar", color: theme.accent) {
                                    Task { await viewModel.downloadClientConfig(client.name) }
                                }
                                actionLink("Remover", color: theme.danger) {
                                    Task { await viewModel.removeClient(client.name) }
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(width: colWidth(0.30), alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .overlay(Divider().background(theme.cardBorder), alignment: .bottom)
                    }
                }
            }
        }
    }

    private var peersSection: some View {
        sectionCard(title: "Peers Conectados", trailing: {
            Text("\(viewModel.peers.filter { $0.online == true }.count) conectados / \(viewModel.peers.count) total")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.muted)
        }) {
            VStack(alignment: .leading, spacing: 10) {
                tableHeader(["CLIENTE", "STATUS", "ORIGEM", "IPS PERMITIDOS", "ULTIMO CONTATO", "TRANSFERENCIA", "ACOES"], widths: [0.17, 0.10, 0.15, 0.14, 0.17, 0.18, 0.09])

                if viewModel.peers.isEmpty {
                    emptyRow("Nenhum peer ativo")
                } else {
                    ForEach(viewModel.peers) { peer in
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(peer.name ?? shortKey(peer.publicKey))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(theme.text)
                                    .lineLimit(1)
                                Text(shortKey(peer.publicKey))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(theme.muted)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(width: colWidth(0.17), alignment: .leading)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(peer.online == true ? theme.success : theme.muted.opacity(0.5))
                                    .frame(width: 7, height: 7)
                                Text(peer.online == true ? "Conectado" : "Desconectado")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(peer.online == true ? theme.success : theme.muted)
                            }
                            .padding(.horizontal, 12)
                            .frame(width: colWidth(0.10), alignment: .leading)
                            tableCell(peer.endpoint ?? "-", width: 0.15, color: theme.muted, truncation: .tail)
                            tableCell(peer.allowedIps ?? "-", width: 0.14, color: theme.muted, truncation: .tail)
                            tableCell(peer.latestHandshake ?? "Nunca", width: 0.17, color: theme.muted, truncation: .tail)
                            transferCell(peer: peer)
                            Button("Desconectar") {
                                Task { await viewModel.disconnectPeer(peer.publicKey) }
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.danger)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .frame(width: colWidth(0.09), alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        .overlay(Divider().background(theme.cardBorder), alignment: .bottom)
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Text("TingleVPN")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(theme.brand)
                Text("Painel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.muted)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(theme.muted)
            }
            Picker("Tema", selection: $themeModeRaw) {
                ForEach(ThemeMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            if viewModel.isAuthenticated {
                Button("Atualizar") {
                    Task { await viewModel.refreshAll() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.muted)
                .disabled(viewModel.isLoading)

                Button("Sair") {
                    Task { await viewModel.logout() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.muted)
                .disabled(viewModel.isLoading)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 38)
        .background(theme.topbar)
    }

    private func sectionCard<Content: View, Trailing: View>(
        title: String,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(theme.text)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(18)
        .background(theme.card)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        sectionCard(title: title, trailing: { EmptyView() }, content: content)
    }

    private func statusMetric(_ label: String, _ value: String, subtitle: String? = nil, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(theme.muted)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ok ? theme.success : theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transferCell(peer: Peer) -> some View {
        Text("↓ \(peer.rx ?? "-") / ↑ \(peer.tx ?? "-")")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(theme.success)
            .lineLimit(1)
            .truncationMode(.tail)
        .padding(.horizontal, 12)
        .frame(width: colWidth(0.18), alignment: .leading)
    }

    private func actionLink(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func tableHeader(_ labels: [String], widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { idx, text in
                Text(text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(theme.muted)
                    .padding(.horizontal, 12)
                    .frame(width: colWidth(widths[idx]), alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .background(theme.cardAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tableCell(
        _ value: String,
        width: CGFloat,
        weight: Font.Weight = .regular,
        color: Color,
        truncation: Text.TruncationMode = .middle
    ) -> some View {
        Text(value)
            .font(.system(size: 12, weight: weight))
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(truncation)
            .padding(.horizontal, 12)
            .frame(width: colWidth(width), alignment: .leading)
    }

    private func emptyRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Spacer()
        }
        .background(theme.cardAlt.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func colWidth(_ ratio: CGFloat) -> CGFloat {
        max(72, (1080 - 90) * ratio)
    }

    private func shortKey(_ key: String) -> String {
        if key.count <= 14 { return key }
        let start = key.prefix(6)
        let end = key.suffix(6)
        return "\(start)...\(end)"
    }

    private func longKey(_ key: String) -> String {
        if key.count <= 26 { return key }
        let start = key.prefix(12)
        let end = key.suffix(12)
        return "\(start)...\(end)"
    }

    private func healthLastFixText() -> String {
        guard let lastFix = viewModel.status?.healthCheck?.lastFix else { return "Ultima correcao: -" }
        return "Ultima correcao: \(lastFix.timestamp)"
    }

    private func daemonText(_ value: Bool?) -> String {
        (value == true) ? "Carregado" : "Nao carregado"
    }

    private func ipForwardingText(_ value: Bool?) -> String {
        (value == true) ? "Ativado" : "Desativado"
    }

    private func healthText(_ value: Bool?) -> String {
        (value == true) ? "Monitorando" : "Inativo"
    }

    private var addClientSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adicionar Cliente")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.text)

            Text("Nome do cliente")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.muted)

            TextField("ex: iphone-joao", text: $addClientName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.cardAlt)
                .foregroundColor(theme.text)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancelar") {
                    showAddClientModal = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.muted)

                Button("Adicionar") {
                    let name = addClientName
                    showAddClientModal = false
                    Task { await viewModel.createClient(name: name) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(addClientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme.card)
    }

    private var renameClientSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Renomear Cliente")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.text)

            Text("Novo nome")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.muted)

            TextField("ex: iphone-joao", text: $renameNewName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.cardAlt)
                .foregroundColor(theme.text)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Cancelar") { showRenameClientModal = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.muted)

                Button("Salvar") {
                    let old = renameOldName
                    let new = renameNewName
                    showRenameClientModal = false
                    Task { await viewModel.renameClient(oldName: old, newName: new) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(theme.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(renameNewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme.card)
    }

    private var qrCodeSheet: some View {
        VStack(spacing: 14) {
            Text("Codigo QR - \(qrClientName)")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(theme.text)

            if let qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .padding(10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ProgressView("Carregando QR...")
                    .tint(theme.muted)
            }

            Button("Fechar") { showQRModal = false }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.muted)
        }
        .padding(20)
        .frame(width: 360, height: 420)
        .background(theme.card)
    }
}

private enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Escuro"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct ThemePalette {
    let bgTop: Color
    let bgBottom: Color
    let topbar: Color
    let card: Color
    let cardAlt: Color
    let cardBorder: Color
    let text: Color
    let muted: Color
    let brand: Color
    let accent: Color
    let success: Color
    let danger: Color

    static let dark = ThemePalette(
        bgTop: Color(red: 5/255, green: 11/255, blue: 25/255),
        bgBottom: Color(red: 3/255, green: 8/255, blue: 19/255),
        topbar: Color(red: 10/255, green: 17/255, blue: 33/255),
        card: Color(red: 13/255, green: 24/255, blue: 47/255),
        cardAlt: Color(red: 17/255, green: 30/255, blue: 56/255),
        cardBorder: Color(red: 28/255, green: 43/255, blue: 72/255),
        text: Color(red: 226/255, green: 232/255, blue: 243/255),
        muted: Color(red: 126/255, green: 141/255, blue: 171/255),
        brand: Color(red: 169/255, green: 139/255, blue: 250/255),
        accent: Color(red: 139/255, green: 92/255, blue: 246/255),
        success: Color(red: 83/255, green: 220/255, blue: 161/255),
        danger: Color(red: 245/255, green: 101/255, blue: 121/255)
    )

    static let light = ThemePalette(
        bgTop: Color(red: 242/255, green: 246/255, blue: 252/255),
        bgBottom: Color(red: 233/255, green: 239/255, blue: 248/255),
        topbar: Color(red: 222/255, green: 230/255, blue: 242/255),
        card: Color(red: 250/255, green: 252/255, blue: 255/255),
        cardAlt: Color(red: 237/255, green: 243/255, blue: 251/255),
        cardBorder: Color(red: 208/255, green: 219/255, blue: 236/255),
        text: Color(red: 22/255, green: 31/255, blue: 56/255),
        muted: Color(red: 84/255, green: 103/255, blue: 141/255),
        brand: Color(red: 100/255, green: 76/255, blue: 184/255),
        accent: Color(red: 109/255, green: 77/255, blue: 222/255),
        success: Color(red: 19/255, green: 138/255, blue: 91/255),
        danger: Color(red: 204/255, green: 61/255, blue: 84/255)
    )
}
