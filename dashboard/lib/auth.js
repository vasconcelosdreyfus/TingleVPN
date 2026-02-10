const bcrypt = require('bcrypt');

// Simple in-memory rate limiter for login attempts
const loginAttempts = new Map();
const MAX_ATTEMPTS = 5;
const WINDOW_MS = 15 * 60 * 1000; // 15 minutes

function rateLimitLogin(req, res, next) {
  const ip = req.ip;
  const now = Date.now();
  const record = loginAttempts.get(ip);

  if (record) {
    // Clean old entries
    if (now - record.firstAttempt > WINDOW_MS) {
      loginAttempts.delete(ip);
    } else if (record.count >= MAX_ATTEMPTS) {
      const retryAfter = Math.ceil((record.firstAttempt + WINDOW_MS - now) / 1000);
      return res.status(429).render('login', {
        error: `Too many attempts. Try again in ${Math.ceil(retryAfter / 60)} minutes.`
      });
    }
  }

  next();
}

function recordLoginAttempt(ip) {
  const now = Date.now();
  const record = loginAttempts.get(ip);
  if (record && now - record.firstAttempt < WINDOW_MS) {
    record.count++;
  } else {
    loginAttempts.set(ip, { count: 1, firstAttempt: now });
  }
}

function clearLoginAttempts(ip) {
  loginAttempts.delete(ip);
}

function requireAuth(req, res, next) {
  if (req.session && req.session.authenticated) {
    return next();
  }
  res.redirect('/login');
}

async function verifyPassword(password) {
  const hash = process.env.DASHBOARD_PASS_HASH;
  if (!hash) return false;
  return bcrypt.compare(password, hash);
}

module.exports = {
  rateLimitLogin,
  recordLoginAttempt,
  clearLoginAttempts,
  requireAuth,
  verifyPassword
};
