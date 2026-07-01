# TingleVPNTray (Native macOS)

Aplicativo nativo de menu bar (tray) para macOS, escrito em SwiftUI/AppKit.

## O que faz

- Roda como app de tray (`NSStatusItem`)
- Abre uma janela nativa com:
  - login
  - status do servidor
  - peers conectados
  - clientes (adicionar/remover)
- Consome a API local do dashboard em `http://127.0.0.1:3000`
- Nao usa WebView

## Requisitos

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`)
- Dashboard Node rodando em `127.0.0.1:3000`

## Rodar em desenvolvimento

```bash
cd native-macos/TingleVPNTray
swift run
```

## Gerar binario release

```bash
cd native-macos/TingleVPNTray
swift build -c release
```

Binario: `.build/release/TingleVPNTray`

## Observacoes

- A sessao de login usa cookie HTTP do proprio backend.
- Se o dashboard responder `401`, o app volta para tela de login automaticamente.
