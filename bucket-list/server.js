const express = require('express');
const { MongoClient, ObjectId } = require('mongodb');
const { exec } = require('child_process');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

// MongoDB connection — expects env vars set via Kubernetes
const MONGO_URI =
  process.env.MONGO_URI ||
  `mongodb://${process.env.MONGO_USER || 'admin'}:${process.env.MONGO_PASSWORD || 'password'}@${process.env.MONGO_HOST || 'localhost'}:${process.env.MONGO_PORT || '27017'}/${process.env.MONGO_DB || 'bucketlist'}?authSource=admin`;

let db;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

async function connectWithRetry() {
  const maxRetries = 10;
  for (let i = 1; i <= maxRetries; i++) {
    try {
      const client = new MongoClient(MONGO_URI);
      await client.connect();
      db = client.db();
      console.log('Connected to MongoDB');
      return;
    } catch (err) {
      console.error(`MongoDB connection attempt ${i}/${maxRetries} failed: ${err.message}`);
      if (i === maxRetries) throw err;
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
}

// ---------------------------------------------------------------------------
// API Routes
// ---------------------------------------------------------------------------

// List tasks — supports query params like ?status=pending
// VULNERABLE: Express parses ?status[$ne]=done into { status: { $ne: "done" } }
// which gets passed straight into MongoDB, enabling NoSQL operator injection.
app.get('/api/tasks', async (req, res) => {
  try {
    const filter = {};
    if (req.query.status) filter.status = req.query.status;
    if (req.query.title) filter.title = req.query.title;
    const tasks = await db.collection('tasks').find(filter).sort({ createdAt: -1 }).toArray();
    res.json(tasks);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Search tasks — accepts arbitrary MongoDB query document
// VULNERABLE: The entire request body is forwarded as a MongoDB query.
// An attacker can send operators like { "$where": "1==1" } or
// { "title": { "$regex": ".*" } } to dump or probe the collection.
app.post('/api/tasks/search', async (req, res) => {
  try {
    const tasks = await db.collection('tasks').find(req.body).toArray();
    res.json(tasks);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Export tasks — generates a file in the requested format
// VULNERABLE: The format parameter is interpolated directly into a shell command,
// allowing command injection. Example: GET /api/tasks/export?format=json;id
app.get('/api/tasks/export', async (req, res) => {
  try {
    const tasks = await db.collection('tasks').find().toArray();
    const format = req.query.format || 'json';
    exec(`echo '${JSON.stringify(tasks)}' | tee /tmp/tasks.${format}`, (err, stdout) => {
      if (err) return res.status(500).json({ error: err.message });
      res.set('Content-Disposition', `attachment; filename="tasks.${format}"`);
      res.type('text/plain').send(stdout);
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Create task
app.post('/api/tasks', async (req, res) => {
  try {
    const task = {
      title: req.body.title,
      description: req.body.description || '',
      status: 'pending',
      createdAt: new Date(),
    };
    const result = await db.collection('tasks').insertOne(task);
    res.status(201).json({ ...task, _id: result.insertedId });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Update task
// VULNERABLE: The request body is used directly as the MongoDB update document.
// Normal client sends: { "$set": { "status": "done" } }
// Attacker can send:   { "$set": { "title": "PWNED", "status": "hacked" } }
// or use $unset, $rename, $currentDate, etc. to poison data.
app.put('/api/tasks/:id', async (req, res) => {
  try {
    const result = await db.collection('tasks').updateOne(
      { _id: new ObjectId(req.params.id) },
      req.body,
    );
    if (result.matchedCount === 0) return res.status(404).json({ error: 'Not found' });
    const updated = await db.collection('tasks').findOne({ _id: new ObjectId(req.params.id) });
    res.json(updated);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Delete task
app.delete('/api/tasks/:id', async (req, res) => {
  try {
    const result = await db.collection('tasks').deleteOne({ _id: new ObjectId(req.params.id) });
    if (result.deletedCount === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ deleted: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Health check
app.get('/api/health', async (_req, res) => {
  try {
    await db.command({ ping: 1 });
    res.json({ status: 'ok', db: 'connected' });
  } catch {
    res.status(503).json({ status: 'degraded', db: 'disconnected' });
  }
});

// SPA fallback
app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------
connectWithRetry().then(() => {
  app.listen(PORT, '0.0.0.0', () =>
    console.log(`Bucket List running on http://0.0.0.0:${PORT}`),
  );
}).catch((err) => {
  console.error('Fatal: could not connect to MongoDB', err);
  process.exit(1);
});
