const fs = require('fs');
const path = require('path');
const QRCode = require('qrcode');
const { exec, WG_CONF, getInterfaceName } = require('./wireguard');

const PROJECT_DIR = path.join(__dirname, '..', '..');
const KEYS_DIR = path.join(PROJECT_DIR, 'keys');
const CONFIGS_DIR = path.join(PROJECT_DIR, 'configs');
const TEMPLATES_DIR = path.join(PROJECT_DIR, 'templates');
const SUBNET = '10.10.10';

/**
 * Build a map of publicKey -> clientName from server config
 */
function getClientMap() {
  const config = readConfig();
  if (!config) return {};

  const map = {};
  const lines = config.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.startsWith('# Cliente:')) {
      const name = line.replace('# Cliente:', '').trim();
      // Look ahead for PublicKey
      for (let j = i + 1; j < Math.min(i + 5, lines.length); j++) {
        const ahead = lines[j].trim();
        if (ahead.startsWith('PublicKey')) {
          const key = ahead.split('=').slice(1).join('=').trim();
          map[key] = name;
          break;
        }
      }
    }
  }

  return map;
}

/**
 * List all configured clients with their details
 */
function listClients() {
  const config = readConfig();
  if (!config) return [];

  const clients = [];
  const lines = config.split('\n');

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.startsWith('# Cliente:')) {
      const name = line.replace('# Cliente:', '').trim();
      const client = { name };

      for (let j = i + 1; j < Math.min(i + 6, lines.length); j++) {
        const ahead = lines[j].trim();
        if (ahead.startsWith('PublicKey')) {
          client.publicKey = ahead.split('=').slice(1).join('=').trim();
        } else if (ahead.startsWith('AllowedIPs')) {
          client.allowedIps = ahead.split('=').slice(1).join('=').trim();
        }
      }

      clients.push(client);
    }
  }

  return clients;
}

/**
 * Find next available IP in 10.10.10.0/24 subnet
 */
function nextAvailableIp() {
  const config = readConfig();
  const usedIps = new Set();

  if (config) {
    const matches = config.match(/10\.10\.10\.\d+/g);
    if (matches) matches.forEach(ip => usedIps.add(ip));
  }
  // Server is always .1
  usedIps.add(`${SUBNET}.1`);

  for (let i = 2; i <= 254; i++) {
    const candidate = `${SUBNET}.${i}`;
    if (!usedIps.has(candidate)) return candidate;
  }

  throw new Error('No available IPs in subnet');
}

/**
 * Generate a new client (port of generate-client.sh to Node.js)
 */
async function generateClient(clientName) {
  // Validate name
  if (!/^[a-zA-Z0-9_-]+$/.test(clientName)) {
    throw new Error('Client name must contain only letters, numbers, hyphens and underscores');
  }

  // Check if already exists
  const configPath = path.join(CONFIGS_DIR, `${clientName}.conf`);
  if (fs.existsSync(configPath)) {
    throw new Error(`Client '${clientName}' already exists`);
  }

  // Check server config exists
  if (!fs.existsSync(WG_CONF)) {
    throw new Error('Server not configured. Run setup-server.sh first.');
  }

  // Ensure dirs exist
  fs.mkdirSync(KEYS_DIR, { recursive: true });
  fs.mkdirSync(CONFIGS_DIR, { recursive: true });

  // Generate keys
  const privateKey = (await exec('wg', ['genkey'])).trim();
  const publicKey = (await exec('wg', ['pubkey'], { input: privateKey })).trim();
  const psk = (await exec('wg', ['genpsk'])).trim();

  // Save keys
  fs.writeFileSync(path.join(KEYS_DIR, `${clientName}_private.key`), privateKey + '\n', { mode: 0o600 });
  fs.writeFileSync(path.join(KEYS_DIR, `${clientName}_public.key`), publicKey + '\n', { mode: 0o600 });
  fs.writeFileSync(path.join(KEYS_DIR, `${clientName}_psk.key`), psk + '\n', { mode: 0o600 });

  // Allocate IP
  const clientIp = nextAvailableIp();

  // Read server public key & endpoint
  const serverPubKey = fs.readFileSync(path.join(KEYS_DIR, 'server_public.key'), 'utf8').trim();
  const duckdnsDomain = process.env.DUCKDNS_DOMAIN;
  if (!duckdnsDomain) throw new Error('DUCKDNS_DOMAIN not set in .env');
  const endpoint = `${duckdnsDomain}.duckdns.org`;

  // Generate client config from template
  const template = fs.readFileSync(path.join(TEMPLATES_DIR, 'client.conf.template'), 'utf8');
  const clientConfig = template
    .replace(/__CLIENT_IP__/g, clientIp)
    .replace(/__CLIENT_PRIVATE_KEY__/g, privateKey)
    .replace(/__SERVER_PUBLIC_KEY__/g, serverPubKey)
    .replace(/__PRESHARED_KEY__/g, psk)
    .replace(/__ENDPOINT__/g, endpoint);

  fs.writeFileSync(configPath, clientConfig, { mode: 0o600 });

  // Append peer to server config
  const peerBlock = `\n# Cliente: ${clientName}\n[Peer]\nPublicKey = ${publicKey}\nPresharedKey = ${psk}\nAllowedIPs = ${clientIp}/32\n`;
  fs.appendFileSync(WG_CONF, peerBlock);

  // Hot-reload if WireGuard is running
  const iface = getInterfaceName();
  let hotReloaded = false;
  if (iface) {
    try {
      // Write PSK to temp file for wg set (it reads from file)
      const tmpPsk = path.join(KEYS_DIR, `.tmp_psk_${clientName}`);
      fs.writeFileSync(tmpPsk, psk + '\n', { mode: 0o600 });
      try {
        await exec('wg', ['set', iface, 'peer', publicKey,
          'preshared-key', tmpPsk,
          'allowed-ips', `${clientIp}/32`]);
        hotReloaded = true;
      } finally {
        fs.unlinkSync(tmpPsk);
      }
    } catch {
      // Not critical - peer will be added on next restart
    }
  }

  // Generate QR data URL
  const qrDataUrl = await QRCode.toDataURL(clientConfig, { width: 300, margin: 2 });

  return {
    name: clientName,
    ip: clientIp,
    endpoint: `${endpoint}:51820`,
    publicKey,
    qrDataUrl,
    hotReloaded
  };
}

/**
 * Remove a client (port of manage.sh remove to Node.js)
 */
async function removeClient(clientName) {
  // Validate name
  if (!/^[a-zA-Z0-9_-]+$/.test(clientName)) {
    throw new Error('Invalid client name');
  }

  const config = readConfig();
  if (!config) throw new Error('Server config not found');

  // Check client exists
  if (!config.includes(`# Cliente: ${clientName}\n`)) {
    throw new Error(`Client '${clientName}' not found`);
  }

  // Get public key before removal
  const lines = config.split('\n');
  let pubkey = null;
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() === `# Cliente: ${clientName}`) {
      for (let j = i + 1; j < Math.min(i + 5, lines.length); j++) {
        if (lines[j].trim().startsWith('PublicKey')) {
          pubkey = lines[j].split('=').slice(1).join('=').trim();
          break;
        }
      }
      break;
    }
  }

  // Remove from active tunnel
  if (pubkey) {
    const iface = getInterfaceName();
    if (iface) {
      try {
        await exec('wg', ['set', iface, 'peer', pubkey, 'remove']);
      } catch {
        // Not critical
      }
    }
  }

  // Remove peer block from config file
  // Pattern: # Cliente: name\n[Peer]\nPublicKey = ...\nPresharedKey = ...\nAllowedIPs = ...\n
  const newConfig = removePeerBlock(config, clientName);
  fs.writeFileSync(WG_CONF, newConfig, { mode: 0o600 });

  // Remove key files and config
  const filesToRemove = [
    path.join(KEYS_DIR, `${clientName}_private.key`),
    path.join(KEYS_DIR, `${clientName}_public.key`),
    path.join(KEYS_DIR, `${clientName}_psk.key`),
    path.join(CONFIGS_DIR, `${clientName}.conf`)
  ];

  for (const f of filesToRemove) {
    try { fs.unlinkSync(f); } catch { /* file may not exist */ }
  }

  return { removed: clientName };
}

/**
 * Get QR code data URL for an existing client config
 */
async function getClientQR(clientName) {
  if (!/^[a-zA-Z0-9_-]+$/.test(clientName)) {
    throw new Error('Invalid client name');
  }

  const configPath = path.join(CONFIGS_DIR, `${clientName}.conf`);
  if (!fs.existsSync(configPath)) {
    throw new Error(`Config for '${clientName}' not found`);
  }

  const configContent = fs.readFileSync(configPath, 'utf8');
  return QRCode.toDataURL(configContent, { width: 300, margin: 2 });
}

// --- Helpers ---

function readConfig() {
  try {
    return fs.readFileSync(WG_CONF, 'utf8');
  } catch {
    return null;
  }
}

function removePeerBlock(config, clientName) {
  const lines = config.split('\n');
  const result = [];
  let skipping = false;

  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() === `# Cliente: ${clientName}`) {
      skipping = true;
      // Also skip blank line before if present
      if (result.length > 0 && result[result.length - 1].trim() === '') {
        result.pop();
      }
      continue;
    }

    if (skipping) {
      const trimmed = lines[i].trim();
      if (trimmed === '[Peer]' || trimmed.startsWith('PublicKey') ||
          trimmed.startsWith('PresharedKey') || trimmed.startsWith('AllowedIPs')) {
        continue;
      }
      if (trimmed === '') {
        skipping = false;
        continue;
      }
      // Non-matching line while skipping means block is done
      skipping = false;
    }

    result.push(lines[i]);
  }

  return result.join('\n');
}

module.exports = {
  getClientMap,
  listClients,
  generateClient,
  removeClient,
  getClientQR
};
