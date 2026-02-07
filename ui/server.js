// server.js
const http = require('http');
const handler = require('serve-handler');
const { createProxyMiddleware } = require('http-proxy-middleware');


const API_URL = 'http://api';

const server = http.createServer((req, res) => {
  // Health check endpoint
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ status: 'healthy', timestamp: new Date().toISOString() }));
  }
  
  // Check if the request is for the API
  if (req.url.startsWith('/api/')) {
    // Set up proxy to your internal API
    const proxy = createProxyMiddleware({
      target: API_URL,
      changeOrigin: true,
    });
    
    return proxy(req, res);
  }
  
  // Otherwise serve static files
  return handler(req, res, {
    public: 'build',
    rewrites: [
      { source: '/**', destination: '/index.html' }
    ]
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Server running at http://localhost:${PORT}`);
});