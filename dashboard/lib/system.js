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
 * Get public IP via external service
 */
async function getPublicIp() {
  try {
    const out = await exec(CURL, ['-s', '--max-time', '5', 'ifconfig.me']);
    return out.trim();
  } catch {
    return null;
  }
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
 * Get full system status object
 */
async function getSystemStatus() {
  const [tunnel, ipForwarding, nat, publicIp, wgDaemon, duckDaemon] = await Promise.all([
    getTunnelStatus(),
    getIpForwarding(),
    getNatRules(),
    getPublicIp(),
    getDaemonStatus('com.tinglevpn.wg'),
    getDaemonStatus('com.tinglevpn.duckdns')
  ]);

  return {
    tunnel,
    ipForwarding,
    nat,
    publicIp,
    daemons: {
      wireguard: wgDaemon,
      duckdns: duckDaemon
    }
  };
}

module.exports = { getSystemStatus, getTunnelStatus, getPublicIp };
