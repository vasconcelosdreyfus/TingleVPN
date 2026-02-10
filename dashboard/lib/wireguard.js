const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

const WG_CONF = '/usr/local/etc/wireguard/wg0.conf';

/**
 * Resolves the real utun interface name from /var/run/wireguard/wg0.name
 */
function getInterfaceName() {
  try {
    return fs.readFileSync('/var/run/wireguard/wg0.name', 'utf8').trim();
  } catch {
    return null;
  }
}

/**
 * Promisified execFile wrapper - always uses array args (no shell injection)
 * Supports opts.input to write to stdin (e.g. for `wg pubkey`)
 */
function exec(cmd, args = [], opts = {}) {
  const { input, ...execOpts } = opts;
  return new Promise((resolve, reject) => {
    const child = execFile(cmd, args, { timeout: 10000, ...execOpts }, (err, stdout, stderr) => {
      if (err) {
        err.stderr = stderr;
        return reject(err);
      }
      resolve(stdout);
    });
    if (input !== undefined) {
      child.stdin.write(input);
      child.stdin.end();
    }
  });
}

/**
 * Check if WireGuard tunnel is active
 */
async function isWgUp() {
  const iface = getInterfaceName();
  if (!iface) return false;
  try {
    await exec('wg', ['show', iface]);
    return true;
  } catch {
    return false;
  }
}

/**
 * Parse output of `wg show <iface>` into structured peer data
 */
async function parseWgShow() {
  const iface = getInterfaceName();
  if (!iface) return { iface: null, peers: [] };

  let output;
  try {
    output = await exec('wg', ['show', iface]);
  } catch {
    return { iface, peers: [] };
  }

  const peers = [];
  let currentPeer = null;

  for (const line of output.split('\n')) {
    const trimmed = line.trim();

    if (trimmed.startsWith('peer:')) {
      if (currentPeer) peers.push(currentPeer);
      currentPeer = { publicKey: trimmed.split('peer:')[1].trim() };
    } else if (currentPeer) {
      if (trimmed.startsWith('endpoint:')) {
        currentPeer.endpoint = trimmed.split('endpoint:')[1].trim();
      } else if (trimmed.startsWith('allowed ips:')) {
        currentPeer.allowedIps = trimmed.split('allowed ips:')[1].trim();
      } else if (trimmed.startsWith('latest handshake:')) {
        currentPeer.latestHandshake = trimmed.split('latest handshake:')[1].trim();
      } else if (trimmed.startsWith('transfer:')) {
        const transfer = trimmed.split('transfer:')[1].trim();
        const parts = transfer.split(',');
        if (parts.length === 2) {
          currentPeer.rxRaw = parts[0].trim();
          currentPeer.txRaw = parts[1].trim();
          // Parse "X.XX MiB received" / "X.XX MiB sent"
          currentPeer.rx = parts[0].replace('received', '').trim();
          currentPeer.tx = parts[1].replace('sent', '').trim();
        }
      } else if (trimmed.startsWith('preshared key:')) {
        currentPeer.hasPsk = true;
      }
    }
  }
  if (currentPeer) peers.push(currentPeer);

  return { iface, peers };
}

/**
 * Read the server config file
 */
function readServerConfig() {
  try {
    return fs.readFileSync(WG_CONF, 'utf8');
  } catch {
    return null;
  }
}

/**
 * Disconnect a peer by public key (remove from running interface, keep in config)
 */
async function disconnectPeer(publicKey) {
  const iface = getInterfaceName();
  if (!iface) throw new Error('WireGuard is not running');

  // Read config to get the peer's allowed IPs and PSK for re-add on restart
  await exec('wg', ['set', iface, 'peer', publicKey, 'remove']);
}

module.exports = {
  WG_CONF,
  getInterfaceName,
  exec,
  isWgUp,
  parseWgShow,
  readServerConfig,
  disconnectPeer
};
