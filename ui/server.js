const http = require('http');
const handler = require('serve-handler');
const { createProxyMiddleware } = require('http-proxy-middleware');

// ----------------------------------
// Runtime Configuration (IMPORTANT)
// ----------------------------------
const API_URL = process.env.API_BASE_URL || 'http://localhost:5000';
const PORT = process.env.PORT || 3000;

// ----------------------------------
// HTTP Server
// ----------------------------------
const server = http.createServer((req, res) => {

  // -----------------------------
  // Health Check (MANDATORY)
  // -----------------------------
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ status: 'ok' }));
  }

  // -----------------------------
  // API Proxy
  // -----------------------------
  if (req.url.startsWith('/api/')) {
    const proxy = createProxyMiddleware({
      target: API_URL,
      changeOrigin: true,
    });

    return proxy(req, res);
  }

  // -----------------------------
  // Serve React Static Files
  // -----------------------------
  return handler(req, res, {
    public: 'build',
    rewrites: [
      { source: '/**', destination: '/index.html' }
    ]
  });
});

// ----------------------------------
// Start Server
// ----------------------------------
server.listen(PORT, () => {
  console.log(`UI server running on port ${PORT}`);
  console.log(`Proxying API requests to ${API_URL}`);
});
