const router = require('express').Router();
const { rateLimitLogin, recordLoginAttempt, clearLoginAttempts, verifyPassword } = require('../lib/auth');

router.get('/login', (req, res) => {
  if (req.session.authenticated) return res.redirect('/');
  res.render('login', { error: null });
});

router.post('/login', rateLimitLogin, async (req, res) => {
  const { username, password } = req.body;
  const expectedUser = process.env.DASHBOARD_USER || 'admin';

  if (username === expectedUser && await verifyPassword(password || '')) {
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

module.exports = router;
