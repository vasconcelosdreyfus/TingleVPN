const router = require('express').Router();
const { requireAuth } = require('../lib/auth');
const { getSystemStatus } = require('../lib/system');
const { parseWgShow } = require('../lib/wireguard');
const { getClientMap, listClients } = require('../lib/clients');

router.get('/', requireAuth, async (req, res) => {
  try {
    const [status, wgData, clients] = await Promise.all([
      getSystemStatus(),
      parseWgShow(),
      Promise.resolve(listClients())
    ]);

    const clientMap = getClientMap();

    // Enrich peers with client names
    const peers = wgData.peers.map(peer => ({
      ...peer,
      name: clientMap[peer.publicKey] || 'Unknown'
    }));

    res.render('dashboard', { status, peers, clients });
  } catch (err) {
    console.error('Dashboard error:', err);
    res.status(500).render('dashboard', {
      status: { tunnel: { up: false }, daemons: {} },
      peers: [],
      clients: [],
      error: err.message
    });
  }
});

module.exports = router;
