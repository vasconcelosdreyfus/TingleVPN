const router = require('express').Router();
const { rateLimitLogin, recordLoginAttempt, clearLoginAttempts, verifyPassword } = require('../lib/auth');

function authenticate(username, password) {
  const expectedUser = process.env.DASHBOARD_USER || 'admin';
  return username === expectedUser && verifyPassword(password || '');
}

router.get('/login', (req, res) => {
  if (req.session.authenticated) return res.redirect('/');
  res.render('login', { error: null });
});

router.post('/login', rateLimitLogin, async (req, res) => {
  const { username, password } = req.body;
  if (await authenticate(username, password)) {
    clearLoginAttempts(req.ip);
    req.session.authenticated = true;
    return res.redirect('/');
  }

  recordLoginAttempt(req.ip);
  res.render('login', { error: 'Invalid credentials' });
});

router.post('/logout', (req, res) => {
  req.session.destroy(() => {
    res.redirect('/login');
  });
});

router.post('/api/login', rateLimitLogin, async (req, res) => {
  const { username, password } = req.body || {};
  if (await authenticate(username, password)) {
    clearLoginAttempts(req.ip);
    req.session.authenticated = true;
    return res.json({ authenticated: true });
  }

  recordLoginAttempt(req.ip);
  return res.status(401).json({ error: 'Invalid credentials' });
});

router.post('/api/logout', (req, res) => {
  req.session.destroy(() => {
    res.json({ success: true });
  });
});

router.get('/api/me', (req, res) => {
  res.json({ authenticated: !!req.session?.authenticated });
});

module.exports = router;
