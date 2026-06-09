// PesaLink demo app — minimal, dependency-free.
// Serves /health (used by the ALB target group + Route 53 in Lab 2)
// and / (returns which instance/AZ served the request, handy for the demo).
const http = require('http');
const os = require('os');

const PORT = process.env.PORT || 8080;

// In Lab 2 you'll flip this to simulate a failure without killing infra.
// For Lab 1 leave it healthy.
let healthy = true;

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(healthy ? 200 : 503, { 'Content-Type': 'text/plain' });
    return res.end(healthy ? 'OK' : 'UNHEALTHY');
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({
    service: 'pesalink',
    servedBy: os.hostname(),
    region: process.env.AWS_REGION || 'unknown',
    clusterEndpoint: process.env.DB_CLUSTER_ENDPOINT || 'unset',
    readerEndpoint: process.env.DB_READER_ENDPOINT || 'unset',
  }, null, 2));
});

server.listen(PORT, () => console.log(`pesalink listening on ${PORT}`));
