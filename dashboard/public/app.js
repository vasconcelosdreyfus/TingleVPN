// TingleVPN Dashboard - Client-side JS

// --- Toast ---
function showToast(message, type) {
  var toast = document.getElementById('toast');
  toast.textContent = message;
  toast.className = 'fixed bottom-4 right-4 z-50 px-4 py-3 rounded-lg text-sm shadow-lg max-w-sm fade-in';
  if (type === 'error') {
    toast.className += ' bg-red-900 border border-red-700 text-red-300';
  } else {
    toast.className += ' bg-green-900 border border-green-700 text-green-300';
  }
  setTimeout(function() { toast.className = 'hidden'; }, 4000);
}

// --- API helpers ---
function api(method, url, body) {
  var opts = {
    method: method,
    headers: { 'Content-Type': 'application/json' }
  };
  if (body) opts.body = JSON.stringify(body);
  return fetch(url, opts).then(function(r) {
    if (r.status === 401) { window.location.href = '/login'; return; }
    return r.json();
  });
}

// --- Polling ---
var POLL_INTERVAL = 10000;

function pollStatus() {
  api('GET', '/api/status').then(function(data) {
    if (!data) return;
    updateStatusGrid(data);
  }).catch(function() {});
}

function pollPeers() {
  api('GET', '/api/peers').then(function(data) {
    if (!data) return;
    updatePeersTable(data.peers || []);
  }).catch(function() {});
}

function pollClients() {
  api('GET', '/api/clients').then(function(data) {
    if (!data) return;
    updateClientsTable(data.clients || []);
  }).catch(function() {});
}

function pollAll() {
  pollStatus();
  pollPeers();
  pollClients();
}

setInterval(pollAll, POLL_INTERVAL);

// --- Status update ---
function updateStatusGrid(s) {
  var grid = document.getElementById('status-grid');
  if (!grid) return;

  var tunnelUp = s.tunnel && s.tunnel.up;
  var ifaceName = s.tunnel && s.tunnel.iface ? s.tunnel.iface : '';

  grid.innerHTML =
    '<div class="space-y-1">' +
      '<p class="text-xs text-gray-500 uppercase tracking-wider">Tunnel</p>' +
      '<div class="flex items-center gap-2">' +
        '<span class="w-2 h-2 rounded-full ' + (tunnelUp ? 'bg-green-400 pulse-dot' : 'bg-red-400') + '"></span>' +
        '<span class="text-sm font-medium ' + (tunnelUp ? 'text-green-400' : 'text-red-400') + '">' +
          (tunnelUp ? 'Active' : 'Inactive') +
        '</span>' +
      '</div>' +
      (ifaceName ? '<p class="text-xs text-gray-500">' + esc(ifaceName) + '</p>' : '') +
    '</div>' +
    '<div class="space-y-1">' +
      '<p class="text-xs text-gray-500 uppercase tracking-wider">IP Forwarding</p>' +
      '<span class="text-sm font-medium ' + (s.ipForwarding ? 'text-green-400' : 'text-red-400') + '">' +
        (s.ipForwarding ? 'Enabled' : 'Disabled') +
      '</span>' +
    '</div>' +
    '<div class="space-y-1">' +
      '<p class="text-xs text-gray-500 uppercase tracking-wider">NAT</p>' +
      '<span class="text-sm font-medium ' + (s.nat ? 'text-green-400' : 'text-yellow-400') + '">' +
        (s.nat ? 'Active' : 'No rules') +
      '</span>' +
    '</div>' +
    '<div class="space-y-1">' +
      '<p class="text-xs text-gray-500 uppercase tracking-wider">Public IP</p>' +
      '<span class="text-sm font-mono text-gray-300">' + esc(s.publicIp || 'N/A') + '</span>' +
    '</div>' +
    '<div class="space-y-1">' +
      '<p class="text-xs text-gray-500 uppercase tracking-wider">WG Daemon</p>' +
      '<span class="text-sm font-medium ' + (s.daemons && s.daemons.wireguard ? 'text-green-400' : 'text-gray-500') + '">' +
        (s.daemons && s.daemons.wireguard ? 'Loaded' : 'Not loaded') +
      '</span>' +
    '</div>' +
    '<div class="space-y-1">' +
      '<p class="text-xs text-gray-500 uppercase tracking-wider">DuckDNS</p>' +
      '<span class="text-sm font-medium ' + (s.daemons && s.daemons.duckdns ? 'text-green-400' : 'text-gray-500') + '">' +
        (s.daemons && s.daemons.duckdns ? 'Loaded' : 'Not loaded') +
      '</span>' +
    '</div>';
}

// --- Peers table update ---
function updatePeersTable(peers) {
  var tbody = document.getElementById('peers-tbody');
  var count = document.getElementById('peers-count');
  if (!tbody) return;

  var onlineCount = peers.filter(function(p) { return p.online; }).length;
  count.textContent = onlineCount + ' online / ' + peers.length + ' total';

  if (peers.length === 0) {
    tbody.innerHTML = '<tr><td colspan="7" class="py-8 text-center text-gray-500">No peers configured</td></tr>';
    return;
  }

  tbody.innerHTML = peers.map(function(p) {
    var transfer = p.rx
      ? '<span class="text-green-400">&darr; ' + esc(p.rx) + '</span>' +
        '<span class="text-gray-600 mx-1">/</span>' +
        '<span class="text-blue-400">&uarr; ' + esc(p.tx) + '</span>'
      : '<span class="text-gray-500">-</span>';

    var statusDot = p.online ? 'bg-green-400 pulse-dot' : 'bg-gray-600';
    var statusText = p.online ? 'text-green-400' : 'text-gray-500';
    var statusLabel = p.online ? 'Online' : 'Offline';

    return '<tr class="border-b border-gray-800/50 hover:bg-gray-800/30" data-peer-key="' + esc(p.publicKey) + '">' +
      '<td class="py-3 pr-4"><div class="font-medium text-white">' + esc(p.name) + '</div>' +
        '<div class="text-xs text-gray-500 font-mono truncate max-w-[180px]">' + esc(p.publicKey) + '</div></td>' +
      '<td class="py-3 pr-4"><div class="flex items-center gap-2">' +
        '<span class="w-2 h-2 rounded-full ' + statusDot + '"></span>' +
        '<span class="text-xs font-medium ' + statusText + '">' + statusLabel + '</span>' +
      '</div></td>' +
      '<td class="py-3 pr-4 font-mono text-gray-300 text-xs">' + esc(p.endpoint || '-') + '</td>' +
      '<td class="py-3 pr-4 font-mono text-gray-300 text-xs">' + esc(p.allowedIps || '-') + '</td>' +
      '<td class="py-3 pr-4 text-gray-300 text-xs">' + esc(p.latestHandshake || 'Never') + '</td>' +
      '<td class="py-3 pr-4 text-xs">' + transfer + '</td>' +
      '<td class="py-3 text-right">' +
        '<button onclick="disconnectPeer(\'' + encodeURIComponent(p.publicKey) + '\', \'' + esc(p.name) + '\')" ' +
          'class="text-xs text-red-400 hover:text-red-300 transition-colors">Disconnect</button>' +
      '</td></tr>';
  }).join('');
}

// --- Clients table update ---
function updateClientsTable(clients) {
  var tbody = document.getElementById('clients-tbody');
  var count = document.getElementById('clients-count');
  if (!tbody) return;

  count.textContent = clients.length + ' client(s)';

  if (clients.length === 0) {
    tbody.innerHTML = '<tr><td colspan="4" class="py-8 text-center text-gray-500">No clients configured</td></tr>';
    return;
  }

  tbody.innerHTML = clients.map(function(c) {
    return '<tr class="border-b border-gray-800/50 hover:bg-gray-800/30">' +
      '<td class="py-3 pr-4 font-medium text-white">' + esc(c.name) + '</td>' +
      '<td class="py-3 pr-4 font-mono text-gray-300 text-xs">' + esc(c.allowedIps || '-') + '</td>' +
      '<td class="py-3 pr-4 font-mono text-gray-500 text-xs truncate max-w-[200px]">' + esc(c.publicKey || '-') + '</td>' +
      '<td class="py-3 text-right space-x-3">' +
        '<button onclick="showQR(\'' + esc(c.name) + '\')" class="text-xs text-vpn-400 hover:text-vpn-300 transition-colors">QR Code</button>' +
        '<button onclick="removeClient(\'' + esc(c.name) + '\')" class="text-xs text-red-400 hover:text-red-300 transition-colors">Remove</button>' +
      '</td></tr>';
  }).join('');
}

// --- Actions ---
function disconnectPeer(encodedKey, name) {
  if (!confirm('Disconnect peer "' + name + '"? They can reconnect automatically.')) return;

  api('POST', '/api/peers/' + encodedKey + '/disconnect').then(function(data) {
    if (data && data.error) { showToast(data.error, 'error'); return; }
    showToast('Peer "' + name + '" disconnected', 'success');
    pollPeers();
  }).catch(function() { showToast('Failed to disconnect peer', 'error'); });
}

function removeClient(name) {
  if (!confirm('Remove client "' + name + '"? This will delete their keys and config permanently.')) return;

  api('DELETE', '/api/clients/' + encodeURIComponent(name)).then(function(data) {
    if (data && data.error) { showToast(data.error, 'error'); return; }
    showToast('Client "' + name + '" removed', 'success');
    pollClients();
    pollPeers();
  }).catch(function() { showToast('Failed to remove client', 'error'); });
}

function showQR(name) {
  api('GET', '/api/clients/' + encodeURIComponent(name) + '/qr').then(function(data) {
    if (data && data.error) { showToast(data.error, 'error'); return; }
    document.getElementById('qr-modal-title').textContent = name;
    document.getElementById('qr-modal-img').src = data.qrDataUrl;
    document.getElementById('qr-modal').classList.remove('hidden');
  }).catch(function() { showToast('Failed to load QR code', 'error'); });
}

function closeQRModal() {
  document.getElementById('qr-modal').classList.add('hidden');
}

// --- Add Client Modal ---
function openAddClientModal() {
  document.getElementById('add-client-form-section').classList.remove('hidden');
  document.getElementById('add-client-result').classList.add('hidden');
  document.getElementById('client-name').value = '';
  document.getElementById('add-client-modal').classList.remove('hidden');
  document.getElementById('client-name').focus();
}

function closeAddClientModal() {
  document.getElementById('add-client-modal').classList.add('hidden');
  // Refresh if a client was just created
  pollClients();
  pollPeers();
}

function addClient(e) {
  e.preventDefault();
  var name = document.getElementById('client-name').value.trim();
  if (!name) return;

  var btn = document.getElementById('add-client-btn');
  btn.disabled = true;
  btn.textContent = 'Generating...';

  api('POST', '/api/clients', { name: name }).then(function(data) {
    btn.disabled = false;
    btn.textContent = 'Generate Client';

    if (data && data.error) {
      showToast(data.error, 'error');
      return;
    }

    // Show QR result
    document.getElementById('add-client-form-section').classList.add('hidden');
    document.getElementById('result-message').textContent = 'Client "' + data.name + '" created!';
    document.getElementById('result-details').textContent = 'IP: ' + data.ip + ' | Endpoint: ' + data.endpoint;
    document.getElementById('result-qr').src = data.qrDataUrl;
    document.getElementById('add-client-result').classList.remove('hidden');

    showToast('Client "' + data.name + '" created successfully', 'success');
  }).catch(function() {
    btn.disabled = false;
    btn.textContent = 'Generate Client';
    showToast('Failed to create client', 'error');
  });
}

// --- Close modals with Escape ---
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    closeAddClientModal();
    closeQRModal();
  }
});

// --- Close modals clicking backdrop ---
document.getElementById('add-client-modal').addEventListener('click', function(e) {
  if (e.target === this) closeAddClientModal();
});
document.getElementById('qr-modal').addEventListener('click', function(e) {
  if (e.target === this) closeQRModal();
});

// --- Escape HTML helper ---
function esc(str) {
  if (!str) return '';
  var d = document.createElement('div');
  d.appendChild(document.createTextNode(str));
  return d.innerHTML;
}
