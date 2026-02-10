const router = require('express').Router();
const { requireAuth } = require('../lib/auth');
const { listClients, generateClient, removeClient, getClientQR } = require('../lib/clients');

router.get('/clients', requireAuth, (req, res) => {
  try {
    const clients = listClients();
    res.json({ clients });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

router.post('/clients', requireAuth, async (req, res) => {
  try {
    const { name } = req.body;
    if (!name) return res.status(400).json({ error: 'Client name is required' });

    const result = await generateClient(name);
    res.json(result);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

router.delete('/clients/:name', requireAuth, async (req, res) => {
  try {
    const { name } = req.params;

    // Validate name format
    if (!/^[a-zA-Z0-9_-]+$/.test(name)) {
      return res.status(400).json({ error: 'Invalid client name' });
    }

    const result = await removeClient(name);
    res.json(result);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

router.get('/clients/:name/qr', requireAuth, async (req, res) => {
  try {
    const { name } = req.params;

    if (!/^[a-zA-Z0-9_-]+$/.test(name)) {
      return res.status(400).json({ error: 'Invalid client name' });
    }

    const qrDataUrl = await getClientQR(name);
    res.json({ qrDataUrl });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

module.exports = router;
