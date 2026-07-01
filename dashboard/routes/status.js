const router = require('express').Router();
const { requireAuth } = require('../lib/auth');
const { getSystemStatus } = require('../lib/system');
const { restartTunnel } = require('../lib/wireguard');

router.get('/status', requireAuth, async (req, res) => {
  try {
    const status = await getSystemStatus();
    res.json(status);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/tunnel/restart', requireAuth, async (req, res) => {
  try {
    const result = await restartTunnel();
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
