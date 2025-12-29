const http = require('http');

const PORT = process.env.PORT || 8080;
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';
const DEBUG_MODE = process.env.DEBUG_MODE === 'true';

const log = (level, message) => {
  const levels = { error: 0, warn: 1, info: 2, debug: 3 };
  const currentLevel = levels[LOG_LEVEL] || 2;
  if (levels[level] <= currentLevel) {
    console.log(`[${new Date().toISOString()}] [${level.toUpperCase()}] ${message}`);
  }
};

const server = http.createServer((req, res) => {
  const { method, url } = req;

  log('debug', `${method} ${url}`);

  // Health check endpoint
  if (url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'healthy', service: 'ui' }));
    return;
  }

  // Readiness check endpoint
  if (url === '/ready') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ready', service: 'ui' }));
    return;
  }

  // Debug endpoint (only in debug mode)
  if (url === '/debug' && DEBUG_MODE) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      service: 'ui',
      env: {
        LOG_LEVEL,
        DEBUG_MODE,
        NODE_ENV: process.env.NODE_ENV,
        DEVELOPER: process.env.DEVELOPER || 'N/A',
        DEBUG_LEVEL: process.env.DEBUG_LEVEL || 'N/A'
      }
    }));
    return;
  }

  // Main UI response
  if (url === '/' || url === '/ui') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
      <!DOCTYPE html>
      <html>
        <head><title>UI Service</title></head>
        <body>
          <h1>UI Service</h1>
          <p>Multi-Tenant GitOps Demo</p>
          <p>Debug Mode: ${DEBUG_MODE ? 'Enabled' : 'Disabled'}</p>
        </body>
      </html>
    `);
    return;
  }

  // 404 for everything else
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not Found' }));
});

server.listen(PORT, () => {
  log('info', `UI Service started on port ${PORT}`);
  log('info', `Log level: ${LOG_LEVEL}`);
  log('info', `Debug mode: ${DEBUG_MODE}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  log('info', 'SIGTERM received, shutting down gracefully');
  server.close(() => {
    log('info', 'Server closed');
    process.exit(0);
  });
});
