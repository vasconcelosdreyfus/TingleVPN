const fs = require('fs');
const { exec, isWgUp, getInterfaceName, WG, PFCTL, SYSCTL, CURL, LAUNCHCTL } = require('./wireguard');

/**
 * Get tunnel status: interface name, listening port, public key
 */
async function getTunnelStatus() {
  const iface = getInterfaceName();
  const up = await isWgUp();

  if (!up || !iface) {
    return { up: false, iface: null };
  }

  let output;
  try {
    output = await exec(WG, ['show', iface]);
  } catch {
    return { up: false, iface };
  }

  const result = { up: true, iface };
  for (const line of output.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('listening port:')) {
      result.listenPort = trimmed.split('listening port:')[1].trim();
    } else if (trimmed.startsWith('public key:')) {
      result.publicKey = trimmed.split('public key:')[1].trim();
    }
  }

  return result;
}

/**
 * Check IP forwarding status
 */
async function getIpForwarding() {
  try {
    const out = await exec(SYSCTL, ['-n', 'net.inet.ip.forwarding']);
    return out.trim() === '1';
  } catch {
    return false;
  }
}

/**
 * Get NAT rules from pfctl anchor
 */
async function getNatRules() {
  try {
    const out = await exec(PFCTL, ['-a', 'com.apple/wireguard', '-s', 'nat']);
    return out.trim() || null;
  } catch {
    return null;
  }
}

/**
 * Get public IP via external service (with cache and fallback)
 */
let cachedIp = null;
let cachedAt = 0;
const IP_CACHE_MS = 60 * 1000; // 1 minuto

const IP_SERVICES = [
  'https://api.ipify.org',
  'https://ifconfig.me',
  'https://icanhazip.com',
];

async function getPublicIp() {
  const now = Date.now();
  if (cachedIp && now - cachedAt < IP_CACHE_MS) {
    return cachedIp;
  }

  for (const service of IP_SERVICES) {
    try {
      const out = await exec(CURL, ['-4', '-s', '--max-time', '3', service]);
      const ip = out.trim();
      if (/^\d{1,3}(\.\d{1,3}){3}$/.test(ip)) {
        cachedIp = ip;
        cachedAt = now;
        return ip;
      }
    } catch {
      // tenta o proximo
    }
  }

  return cachedIp || null;
}

/**
 * Check LaunchDaemon status
 */
async function getDaemonStatus(label) {
  try {
    await exec(LAUNCHCTL, ['list', label]);
    return true;
  } catch {
    return false;
  }
}

/**
 * Get last health check correction from log
 */
function getLastHealthFix() {
  const logPath = '/var/log/tinglevpn-health.log';
  try {
    const content = fs.readFileSync(logPath, 'utf8');
    const lines = content.trim().split('\n').filter(l => l.includes('CORRIGIDO:'));
    if (lines.length === 0) return null;
    const last = lines[lines.length - 1];
    // Format: "2026-02-21 18:06:40 [HEALTH] CORRIGIDO: ..."
    const match = last.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \[HEALTH\] CORRIGIDO: (.+)$/);
    if (!match) return null;
    return { timestamp: match[1], message: match[2] };
  } catch {
    return null;
  }
}

/**
 * Get full system status object
 */
async function getSystemStatus() {
  const [tunnel, ipForwarding, nat, publicIp, wgDaemon, duckDaemon, healthDaemon] = await Promise.all([
    getTunnelStatus(),
    getIpForwarding(),
    getNatRules(),
    getPublicIp(),
    getDaemonStatus('com.tinglevpn.wg'),
    getDaemonStatus('com.tinglevpn.duckdns'),
    getDaemonStatus('com.tinglevpn.health')
  ]);

  return {
    tunnel,
    ipForwarding,
    nat,
    publicIp,
    daemons: {
      wireguard: wgDaemon,
      duckdns: duckDaemon,
      health: healthDaemon
    },
    healthCheck: {
      active: healthDaemon,
      lastFix: getLastHealthFix()
    }
  };
}

module.exports = { getSystemStatus, getTunnelStatus, getPublicIp };
