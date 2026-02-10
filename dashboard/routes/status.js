const router = require('express').Router();
const { requireAuth } = require('../lib/auth');
const { getSystemStatus } = require('../lib/system');

router.get('/status', requireAuth, async (req, res) => {
  try {
    const status = await getSystemStatus();
    res.json(status);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
