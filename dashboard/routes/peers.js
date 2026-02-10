const router = require('express').Router();
const { requireAuth } = require('../lib/auth');
const { parseWgShow, disconnectPeer } = require('../lib/wireguard');
const { getClientMap } = require('../lib/clients');

router.get('/peers', requireAuth, async (req, res) => {
  try {
    const wgData = await parseWgShow();
    const clientMap = getClientMap();

    const peers = wgData.peers.map(peer => ({
      ...peer,
      name: clientMap[peer.publicKey] || 'Unknown'
    }));

    res.json({ peers });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/peers/:key/disconnect', requireAuth, async (req, res) => {
  try {
    const publicKey = decodeURIComponent(req.params.key);

    // Validate it looks like a WireGuard public key (base64, 44 chars)
    if (!/^[A-Za-z0-9+/]{42,44}=?$/.test(publicKey)) {
      return res.status(400).json({ error: 'Invalid public key format' });
    }

    await disconnectPeer(publicKey);
    res.json({ success: true, message: 'Peer disconnected' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
