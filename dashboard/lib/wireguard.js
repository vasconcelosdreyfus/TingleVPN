const { execFile } = require('child_process');
const fs = require('fs');
const path = require('path');

const WG_CONF = '/usr/local/etc/wireguard/wg0.conf';

// Full paths for commands - LaunchDaemons have minimal PATH
const WG = '/opt/homebrew/bin/wg';
const WG_QUICK = '/opt/homebrew/bin/wg-quick';
const PFCTL = '/sbin/pfctl';
const SYSCTL = '/usr/sbin/sysctl';
const CURL = '/usr/bin/curl';
const LAUNCHCTL = '/bin/launchctl';

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
    await exec(WG, ['show', iface]);
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
    output = await exec(WG, ['show', iface]);
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

  // Mark online/offline based on handshake age (3 min threshold)
  for (const peer of peers) {
    const ageSec = parseHandshakeAge(peer.latestHandshake);
    peer.online = ageSec !== null && ageSec < 180;
  }

  return { iface, peers };
}

/**
 * Parse "X minutes, Y seconds ago" into total seconds. Returns null if unparseable.
 */
function parseHandshakeAge(str) {
  if (!str) return null;
  let total = 0;
  const parts = str.match(/(\d+)\s+(second|minute|hour|day)/g);
  if (!parts) return null;
  for (const part of parts) {
    const [, num, unit] = part.match(/(\d+)\s+(second|minute|hour|day)/);
    const n = parseInt(num, 10);
    if (unit.startsWith('second')) total += n;
    else if (unit.startsWith('minute')) total += n * 60;
    else if (unit.startsWith('hour')) total += n * 3600;
    else if (unit.startsWith('day')) total += n * 86400;
  }
  return total;
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
  await exec(WG, ['set', iface, 'peer', publicKey, 'remove']);
}

/**
 * Clean up stale WireGuard runtime files that prevent restart
 */
function cleanStaleFiles() {
  const runDir = '/var/run/wireguard';
  try {
    const nameFile = path.join(runDir, 'wg0.name');
    const sockFile = path.join(runDir, 'wg0.sock');
    const iface = fs.readFileSync(nameFile, 'utf8').trim();

    // Check if the interface actually exists by trying to read its flags
    try {
      require('child_process').execFileSync('/sbin/ifconfig', [iface], { timeout: 3000 });
      // Interface exists, don't clean
    } catch {
      // Interface doesn't exist - stale files
      try { fs.unlinkSync(nameFile); } catch {}
      try { fs.unlinkSync(sockFile); } catch {}
    }
  } catch {
    // No stale files to clean
  }
}

/**
 * Restart the WireGuard tunnel (down + clean stale + up)
 * Returns { success, message }
 */
async function restartTunnel() {
  // Try graceful down first
  try {
    await exec(WG_QUICK, ['down', 'wg0'], { timeout: 15000 });
  } catch {
    // May fail if tunnel wasn't running - that's OK
  }

  // Clean stale runtime files
  cleanStaleFiles();

  // Small delay to let the system release resources
  await new Promise(r => setTimeout(r, 1000));

  // Bring tunnel up
  try {
    await exec(WG_QUICK, ['up', 'wg0'], { timeout: 15000 });
    return { success: true, message: 'Tunnel restarted successfully' };
  } catch (err) {
    // Retry once after more aggressive cleanup
    cleanStaleFiles();
    await new Promise(r => setTimeout(r, 2000));
    try {
      await exec(WG_QUICK, ['up', 'wg0'], { timeout: 15000 });
      return { success: true, message: 'Tunnel restarted (2nd attempt)' };
    } catch (err2) {
      throw new Error(`Failed to restart tunnel: ${err2.message || err2.stderr || 'unknown error'}`);
    }
  }
}

module.exports = {
  WG_CONF,
  WG,
  WG_QUICK,
  PFCTL,
  SYSCTL,
  CURL,
  LAUNCHCTL,
  getInterfaceName,
  exec,
  isWgUp,
  parseWgShow,
  readServerConfig,
  disconnectPeer,
  restartTunnel
};
