const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const mongoSanitize = require('mongo-sanitize');
require('dotenv').config();

const app = express();
const PORT = Number(process.env.PORT) || 5000;
const mongoURI = process.env.MONGO_URI;
const jwtSecret = process.env.JWT_SECRET;
const isProduction = process.env.NODE_ENV === 'production';

if (isProduction) {
  app.set('trust proxy', 1);
}

if (!mongoURI) {
  console.error('MongoDB connection error: MONGO_URI is not defined in environment');
  process.exit(1);
}

if (!jwtSecret || jwtSecret.length < 32) {
  console.error('JWT_SECRET is missing or too short. Use at least 32 characters.');
  process.exit(1);
}

const allowedOrigins = new Set();
const frontendOrigins = (process.env.FRONTEND_URLS || process.env.FRONTEND_URL || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

frontendOrigins.forEach((origin) => allowedOrigins.add(origin));

if (!isProduction) {
  allowedOrigins.add('http://localhost:3000');
}

if (isProduction && allowedOrigins.size === 0) {
  console.error('FRONTEND_URL or FRONTEND_URLS must be set in production (for strict CORS).');
  process.exit(1);
}

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 1000,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many requests. Please try again later.',
  },
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many authentication attempts. Please try again later.',
  },
});

app.disable('x-powered-by');
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
}));

app.use(cors({
  origin(origin, callback) {
    if (!origin || allowedOrigins.has(origin)) {
      return callback(null, true);
    }

    return callback(new Error('CORS policy violation'));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

app.use(express.json({ limit: '10kb' }));
app.use((req, _res, next) => {
  if (req.body && typeof req.body === 'object') {
    req.body = mongoSanitize(req.body);
  }
  next();
});

app.use('/api', apiLimiter);
app.use('/api/auth', authLimiter);

// Routes
app.get('/', (_req, res) => res.send('Task Manager API is running...'));
app.use('/api/auth', require('./routes/auth'));
app.use('/api/tasks', require('./routes/tasks'));

if (process.env.ENABLE_PUBLIC_TASKMANAGER === 'true') {
  app.use('/api/taskmanager', require('./routes/taskmanager'));
}

app.use((err, _req, res, next) => {
  if (err && err.message === 'CORS policy violation') {
    return res.status(403).json({
      success: false,
      message: 'Origin not allowed',
    });
  }

  return next(err);
});

app.use((err, _req, res, _next) => {
  console.error('Unhandled server error:', err);
  res.status(500).json({
    success: false,
    message: 'Internal server error',
  });
});

async function start() {
  try {
    await mongoose.connect(mongoURI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });

    console.log('MongoDB connected successfully');
    app.listen(PORT, () => console.log(`Server is running on port ${PORT}`));
  } catch (err) {
    console.error('MongoDB connection error:', err);
    process.exit(1);
  }
}

start();