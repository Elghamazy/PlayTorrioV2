import express from 'express';
import WebTorrent from 'webtorrent';
import cors from 'cors';

const app = express();
const client = new WebTorrent({
  tracker: {
    announce: [
      'wss://tracker.openwebtorrent.com',
      'wss://tracker.sloppyta.co',
      'wss://tracker.timhaswell.co.uk:2124',
    ],
  },
});

const torrents = new Map();

app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'ok', torrents: torrents.size });
});

app.post('/torrent/add', (req, res) => {
  const { magnet } = req.body;
  
  if (!magnet || !magnet.startsWith('magnet:')) {
    return res.status(400).json({ error: 'Invalid magnet link' });
  }

  if (torrents.has(magnet)) {
    const existing = torrents.get(magnet);
    return res.json({
      hash: existing.infoHash,
      files: existing.files.map((f, i) => ({ index: i, name: f.name, size: f.length })),
      ready: existing.ready
    });
  }

  const torrent = client.add(magnet);

  torrent.on('ready', () => {
    torrents.set(magnet, torrent);
    console.log(`Torrent ready: ${torrent.infoHash}`);
  });

  torrent.on('error', (err) => {
    console.error(`Torrent error: ${err.message}`);
  });

  res.json({ 
    hash: torrent.infoHash,
    ready: false
  });
});

app.get('/torrent/:hash/files', (req, res) => {
  const { hash } = req.params;
  
  const torrent = Array.from(torrents.values()).find(t => t.infoHash === hash);
  if (!torrent || !torrent.ready) {
    return res.status(404).json({ error: 'Torrent not found or not ready' });
  }

  const files = torrent.files.map((file, index) => ({
    index,
    name: file.name,
    size: file.length,
  }));

  res.json({ hash: torrent.infoHash, files });
});

app.get('/torrent/:hash/stream', (req, res) => {
  const { hash } = req.params;
  const { file } = req.query;
  
  const torrent = Array.from(torrents.values()).find(t => t.infoHash === hash);
  if (!torrent || !torrent.ready) {
    return res.status(404).json({ error: 'Torrent not found or not ready' });
  }

  const fileIndex = file !== undefined ? parseInt(file) : 0;
  const selectedFile = torrent.files[fileIndex] || torrent.files[0];
  
  if (!selectedFile) {
    return res.status(404).json({ error: 'File not found' });
  }

  const range = req.headers.range;
  if (!range) {
    return res.status(416).json({ error: 'Range header required' });
  }

  const fileSize = selectedFile.length;
  const parts = range.replace(/bytes=/, '').split('-');
  const start = parseInt(parts[0], 10);
  const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
  const chunkSize = end - start + 1;

  res.set({
    'Content-Range': `bytes ${start}-${end}/${fileSize}`,
    'Accept-Ranges': 'bytes',
    'Content-Length': chunkSize,
    'Content-Type': 'application/octet-stream',
  });

  res.status(206);
  
  const stream = selectedFile.createReadStream({ start, end });
  stream.pipe(res);
});

app.get('/torrent/:hash/status', (req, res) => {
  const { hash } = req.params;
  
  const torrent = Array.from(torrents.values()).find(t => t.infoHash === hash);
  if (!torrent) {
    return res.status(404).json({ error: 'Torrent not found' });
  }

  res.json({
    hash: torrent.infoHash,
    ready: torrent.ready,
    downloaded: torrent.downloaded || 0,
    total: torrent.length || 0,
    progress: torrent.length > 0 ? ((torrent.downloaded || 0) / torrent.length) * 100 : 0,
    speed: torrent.downloadSpeed || 0,
    peers: torrent.numPeers || 0,
    seeding: torrent.seeding || false,
  });
});

app.delete('/torrent/:hash', (req, res) => {
  const { hash } = req.params;
  
  const torrent = Array.from(torrents.values()).find(t => t.infoHash === hash);
  if (!torrent) {
    return res.status(404).json({ error: 'Torrent not found' });
  }

  torrent.destroy();
  torrents.delete(hash);
  
  res.json({ success: true });
});

const PORT = process.env.PORT || 7860;
app.listen(PORT, () => {
  console.log(`StreamVault backend running on port ${PORT}`);
});