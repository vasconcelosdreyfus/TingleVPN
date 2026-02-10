require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const express = require('express');
const session = require('express-session');
const path = require('path');

const app = express();

// View engine
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Body parsing
app.use(express.json());
app.use(express.urlencoded({ extended: false }));

// Static files
app.use('/public', express.static(path.join(__dirname, 'public')));

// Session
app.use(session({
  secret: process.env.DASHBOARD_SECRET || 'change-me-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    maxAge: 24 * 60 * 60 * 1000 // 24h
  }
}));

// Routes
app.use('/', require('./routes/auth'));
app.use('/', require('./routes/dashboard'));
app.use('/api', require('./routes/status'));
app.use('/api', require('./routes/peers'));
app.use('/api', require('./routes/clients'));

const PORT = parseInt(process.env.DASHBOARD_PORT, 10) || 3000;
const BIND = process.env.DASHBOARD_BIND || '127.0.0.1';

app.listen(PORT, BIND, () => {
  console.log(`TingleVPN Dashboard running on http://${BIND}:${PORT}`);
});
