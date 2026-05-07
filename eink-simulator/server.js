// Fan-out WebSocket relay for Kirole E-ink simulator.
// iOS SimulatorBridge connects here; web simulator (index.html) connects here.
// Anything one client sends is rebroadcast to every other client. No routing.

import { WebSocketServer } from 'ws';

const PORT = Number(process.env.RELAY_PORT) || 3456;
const wss = new WebSocketServer({ port: PORT });

let nextId = 1;

wss.on('connection', (socket, request) => {
  const id = nextId++;
  const origin = request.socket.remoteAddress ?? 'unknown';
  console.log(`[relay] client #${id} connected from ${origin} (total: ${wss.clients.size})`);

  socket.on('message', (data, isBinary) => {
    const preview = isBinary ? `<binary ${data.length}B>` : data.toString().slice(0, 80);
    console.log(`[relay] #${id} -> ${preview}`);
    for (const peer of wss.clients) {
      if (peer !== socket && peer.readyState === peer.OPEN) {
        peer.send(data, { binary: isBinary });
      }
    }
  });

  socket.on('close', () => {
    console.log(`[relay] client #${id} disconnected (remaining: ${wss.clients.size - 1})`);
  });

  socket.on('error', (err) => {
    console.error(`[relay] client #${id} error: ${err.message}`);
  });
});

wss.on('listening', () => {
  console.log(`[relay] listening on ws://localhost:${PORT}`);
});
