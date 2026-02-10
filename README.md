# TingleVPN

VPN pessoal com WireGuard no macOS. Permite rotear todo o trafego de internet (notebook e celular) atraves do seu desktop Mac no Brasil, mantendo um IP brasileiro enquanto voce viaja.

100% self-hosted, sem custos com terceiros.

## Arquitetura

```
[Viajando]                              [Desktop macOS no Brasil]
 Notebook/Celular  ── WireGuard ──►    Servidor VPN (10.10.10.1)
                                            │ NAT (pfctl)
                                       Internet brasileira
```

- **VPN**: WireGuard (open-source, gratuito)
- **DNS Dinamico**: DuckDNS (gratuito)
- **Subnet**: 10.10.10.0/24, porta 51820/UDP
- **NAT**: pfctl com anchor `com.apple/wireguard`

## Pre-requisitos

### No Mac (servidor)

1. **macOS** com acesso de administrador
2. **Homebrew** instalado ([brew.sh](https://brew.sh))
3. **Port forwarding** configurado no roteador: porta **51820/UDP** apontando para o IP local do Mac
4. **Conta DuckDNS** gratuita em [duckdns.org](https://www.duckdns.org)
5. **Sleep desabilitado** no Mac:
   ```bash
   sudo pmset -a sleep 0
   ```

### Nos dispositivos (clientes)

- **iPhone/iPad**: App [WireGuard](https://apps.apple.com/app/wireguard/id1441195209) (gratuito)
- **Mac/notebook**: `brew install wireguard-tools` ou app WireGuard da Mac App Store
- **Android**: App [WireGuard](https://play.google.com/store/apps/details?id=com.wireguard.android) (gratuito)

## Setup Inicial

### 1. Crie o arquivo .env

```bash
cd tinglevpn
cat > .env << 'EOF'
DUCKDNS_DOMAIN=seu-subdominio
DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
EOF
```

Substitua pelos seus dados do DuckDNS. O dominio completo sera `seu-subdominio.duckdns.org`.

### 2. Execute o setup

```bash
sudo ./setup-server.sh
```

O script vai:
- Instalar `wireguard-tools` e `qrencode` via Homebrew
- Gerar as chaves do servidor
- Criar a config em `/usr/local/etc/wireguard/wg0.conf`
- Instalar os scripts de NAT (postup/postdown)
- Instalar os LaunchDaemons para auto-start

### 3. Inicie o servidor

```bash
sudo ./manage.sh start
```

### 4. Verifique o status

```bash
sudo ./manage.sh status
```

## Adicionando Clientes

### Gerar config de um novo cliente

```bash
sudo ./generate-client.sh iphone
```

O script gera automaticamente:
- Par de chaves + PSK (preshared key)
- IP na subnet 10.10.10.0/24
- Arquivo de config em `configs/iphone.conf`
- QR code no terminal (para escanear no celular)

### Conectar no iPhone/iPad

1. Abra o app WireGuard
2. Toque em "+" > "Criar a partir de QR code"
3. Escaneie o QR code exibido no terminal
4. Ative o tunel

### Conectar no Mac (notebook)

**Opcao 1: App WireGuard (mais simples)**
1. Abra o app WireGuard
2. "Importar tunel(is) de arquivo" > selecione `configs/nome.conf`
3. Ative o tunel

**Opcao 2: CLI**
```bash
# Copie a config para o notebook
scp usuario@servidor:~/apps/tinglevpn/configs/notebook.conf /usr/local/etc/wireguard/
# Conecte
sudo wg-quick up notebook
# Desconecte
sudo wg-quick down notebook
```

## Gerenciamento

Todos os comandos de gerenciamento estao em `manage.sh`:

```bash
sudo ./manage.sh start       # Inicia WireGuard + LaunchDaemons
sudo ./manage.sh stop        # Para tudo
sudo ./manage.sh restart     # Reinicia WireGuard
sudo ./manage.sh status      # Status completo (tunel, NAT, peers)
sudo ./manage.sh list        # Lista clientes configurados
sudo ./manage.sh add <nome>  # Adiciona novo cliente
sudo ./manage.sh remove <nome>  # Remove um cliente
sudo ./manage.sh logs        # Mostra logs recentes
sudo ./manage.sh ip          # Mostra IP publico atual
sudo ./manage.sh duckdns     # Forca atualizacao do DuckDNS
sudo ./manage.sh dashboard <cmd>  # Gerencia o dashboard web (start|stop|restart|status)
```

## Dashboard Web

Painel web para monitorar e gerenciar a VPN pelo navegador. Mostra status do servidor, peers conectados (online/offline em tempo real), e permite adicionar/remover clientes com QR code.

### Setup do Dashboard

```bash
# Instalar dependencias
cd dashboard && npm install && cd ..

# Configurar credenciais no .env
# Gerar hash da senha:
node -e "require('./dashboard/node_modules/bcrypt').hash('sua-senha',10).then(console.log)"

# Adicionar ao .env:
DASHBOARD_USER=admin
DASHBOARD_PASS_HASH=<hash-gerado>
DASHBOARD_SECRET=<string-aleatoria>
DASHBOARD_PORT=3000
DASHBOARD_BIND=127.0.0.1
```

### Iniciar o Dashboard

```bash
# Como LaunchDaemon (recomendado - auto-start no boot)
sudo ./manage.sh dashboard start

# Ou manualmente
cd dashboard && npm start
```

### Acessar

Abra `http://127.0.0.1:3000` no navegador e faca login com as credenciais configuradas.

### Gerenciar o Dashboard

```bash
sudo ./manage.sh dashboard start    # Iniciar
sudo ./manage.sh dashboard stop     # Parar
sudo ./manage.sh dashboard restart  # Reiniciar
sudo ./manage.sh dashboard status   # Verificar status
```

### Funcionalidades

- **Server Status**: Tunnel, IP forwarding, NAT, IP publico, daemons
- **Connected Peers**: Peers com status online/offline, endpoint, handshake, transferencia, disconnect
- **Configured Clients**: Lista de clientes, QR code, adicionar/remover clientes
- **Auto-refresh**: Polling a cada 10 segundos

## Configuracao do Roteador

Para que dispositivos externos alcancem o servidor VPN:

1. Acesse o painel do roteador (geralmente `192.168.0.1` ou `192.168.1.1`)
2. Encontre a secao de **Port Forwarding** / **Redirecionamento de Portas**
3. Crie uma regra:
   - **Porta externa**: 51820
   - **Protocolo**: UDP
   - **IP interno**: IP local do Mac (ex: `192.168.0.100`)
   - **Porta interna**: 51820
4. Salve e aplique

Dica: configure um IP fixo (DHCP reservation) para o Mac no roteador.

## Estrutura do Projeto

```
tinglevpn/
├── .gitignore                        # Ignora keys/, configs/, .env
├── .env                              # Credenciais DuckDNS + config dashboard
├── README.md                         # Este arquivo
├── setup-server.sh                   # Setup inicial do servidor
├── generate-client.sh                # Gera config de novo cliente + QR code
├── manage.sh                         # CLI de gerenciamento
├── duckdns-update.sh                 # Atualizador de DNS dinamico
├── scripts/
│   ├── postup.sh                     # Ativa NAT via pfctl
│   └── postdown.sh                   # Desativa NAT
├── templates/
│   ├── wg0.conf.template             # Template do servidor
│   ├── client.conf.template          # Template do cliente
│   ├── com.tinglevpn.wg.plist        # LaunchDaemon WireGuard
│   ├── com.tinglevpn.duckdns.plist   # LaunchDaemon DuckDNS
│   └── com.tinglevpn.dashboard.plist # LaunchDaemon Dashboard
├── dashboard/                        # Painel web (Node.js/Express)
│   ├── server.js                     # Entry point
│   ├── lib/                          # Logica de negocio
│   ├── routes/                       # Rotas Express
│   ├── views/                        # Templates EJS
│   └── public/                       # JS client-side
├── configs/                          # Configs geradas dos clientes (gitignored)
└── keys/                             # Chaves privadas (gitignored)
```

## Troubleshooting

### WireGuard nao inicia

```bash
# Verifique se o wireguard-tools esta instalado
which wg wg-quick

# Verifique a config
cat /usr/local/etc/wireguard/wg0.conf

# Tente iniciar manualmente com debug
sudo wg-quick up wg0
```

### Cliente conecta mas nao navega

```bash
# Verifique IP forwarding
sysctl net.inet.ip.forwarding
# Deve ser 1. Se nao:
sudo sysctl -w net.inet.ip.forwarding=1

# Verifique regras NAT
sudo pfctl -a com.apple/wireguard -s nat
# Deve mostrar a regra de NAT

# Verifique se o peer esta conectado
sudo wg show wg0
```

### DuckDNS nao atualiza

```bash
# Teste manualmente
sudo ./manage.sh duckdns

# Verifique o .env
cat .env

# Verifique logs
cat /var/log/tinglevpn-duckdns.log
```

### Permitir wireguard-go no firewall

Se o firewall do macOS estiver ativo, pode ser necessario permitir o `wireguard-go`:

1. Preferencias do Sistema > Seguranca e Privacidade > Firewall
2. Opcoes de Firewall > "+" > encontre `wireguard-go`
3. Permita conexoes de entrada

### Verificar se a VPN esta funcionando

No dispositivo cliente, apos conectar:

```bash
# Deve mostrar o IP brasileiro do seu Mac
curl ifconfig.me
```

## Seguranca

- Chaves privadas ficam em `keys/` (gitignored)
- Configs dos clientes ficam em `configs/` (gitignored)
- Token do DuckDNS fica no `.env` (gitignored)
- PSK (preshared key) ativado para protecao extra contra computacao quantica
- NAT usa anchor isolado (`com.apple/wireguard`), nao modifica arquivos do sistema
