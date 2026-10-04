import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import crypto from 'node:crypto';
import admin from 'firebase-admin';
import { z } from 'zod';
import db from './db.js';

const app = express();
app.use(cors({ origin: process.env.CORS_ORIGIN?.split(',') || true }));
app.use(express.json({ limit: '2mb' }));

if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
}

async function authenticate(req, res, next) {
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, '');
  if (token && admin.apps.length) {
    try {
      const user = await admin.auth().verifyIdToken(token);
      req.user = { id: user.uid, name: user.name || user.email || 'Team member', role: user.role || 'cashier' };
      return next();
    } catch { return res.status(401).json({ error: 'Invalid or expired Firebase token' }); }
  }
  if (process.env.NODE_ENV !== 'production' && req.headers['x-demo-role']) {
    req.user = { id: 'demo-user', name: 'Demo operator', role: req.headers['x-demo-role'] };
    return next();
  }
  return res.status(401).json({ error: 'Sign in required. Configure Firebase or use x-demo-role in development.' });
}
const allow = (...roles) => (req, res, next) => roles.includes(req.user.role) ? next() : res.status(403).json({ error: 'Insufficient role permissions' });
const route = (handler) => (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
const itemSchema = z.object({ name: z.string().trim().min(1).max(120), sku: z.string().trim().min(1).max(48), price: z.number().nonnegative(), unit: z.string().trim().min(1).max(24), stock: z.number().nonnegative(), low_stock: z.number().nonnegative().default(5), image_url: z.string().url().optional().or(z.literal('')), gst_rate: z.number().min(0).max(100).default(0), hsn_sac: z.string().trim().max(16).default('') });
const id = () => crypto.randomUUID();
const fields = 'id, name, sku, price, unit, stock, low_stock, image_url, gst_rate, hsn_sac, updated_at';

app.get('/api/health', (_req, res) => res.json({ status: 'ok', database: db.dialect }));
app.use('/api', authenticate);

app.get('/api/items', route(async (_req, res) => {
  const { rows } = await db.query(`SELECT ${fields} FROM items ORDER BY name`);
  res.json(rows);
}));
app.post('/api/items', allow('admin'), route(async (req, res) => {
  const value = itemSchema.parse(req.body); const itemId = id();
  await db.query('INSERT INTO items(id,name,sku,price,unit,stock,low_stock,image_url,gst_rate,hsn_sac,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)', [itemId, value.name, value.sku, value.price, value.unit, value.stock, value.low_stock, value.image_url || null, value.gst_rate, value.hsn_sac, new Date().toISOString()]);
  const { rows } = await db.query(`SELECT ${fields} FROM items WHERE id = ?`, [itemId]);
  res.status(201).json(rows[0]);
}));
app.put('/api/items/:id', allow('admin'), route(async (req, res) => {
  const value = itemSchema.parse(req.body);
  const result = await db.query('UPDATE items SET name=?,sku=?,price=?,unit=?,stock=?,low_stock=?,image_url=?,gst_rate=?,hsn_sac=?,updated_at=? WHERE id=?', [value.name, value.sku, value.price, value.unit, value.stock, value.low_stock, value.image_url || null, value.gst_rate, value.hsn_sac, new Date().toISOString(), req.params.id]);
  if (!result.changes) return res.status(404).json({ error: 'Item not found' });
  const { rows } = await db.query(`SELECT ${fields} FROM items WHERE id = ?`, [req.params.id]); res.json(rows[0]);
}));
app.delete('/api/items/:id', allow('admin'), route(async (req, res) => {
  const result = await db.query('DELETE FROM items WHERE id=?', [req.params.id]);
  result.changes ? res.status(204).end() : res.status(404).json({ error: 'Item not found' });
}));

app.post('/api/sales', allow('admin', 'cashier'), route(async (req, res) => {
  const body = z.object({ payment_mode: z.enum(['Cash', 'UPI', 'Card', 'Other']), supply_type: z.enum(['intra_state', 'inter_state']).default('intra_state'), place_of_supply: z.string().trim().max(80).default(''), lines: z.array(z.object({ item_id: z.string(), quantity: z.number().positive() })).min(1) }).parse(req.body);
  const saleId = id(); const created = new Date().toISOString(); let sale;
  await db.transaction(async (tx) => {
    const sequence = await tx.query('UPDATE invoice_sequence SET value=value+1 WHERE id=1 RETURNING value');
    const date = new Date(created); const financialYear = date.getUTCMonth() >= 3 ? date.getUTCFullYear() : date.getUTCFullYear() - 1;
    const invoiceNo = `INV/${String(financialYear).slice(-2)}-${String((financialYear + 1) % 100).padStart(2, '0')}/${String(sequence.rows[0].value).padStart(5, '0')}`;
    let subtotal = 0; let tax = 0; const lines = [];
    for (const entry of body.lines) {
      const result = await tx.query('SELECT id,name,price,stock,gst_rate,hsn_sac FROM items WHERE id=?', [entry.item_id]);
      const item = result.rows[0];
      if (!item || Number(item.stock) < entry.quantity) throw Object.assign(new Error(`Insufficient stock for ${item?.name || entry.item_id}`), { status: 409 });
      const base = Number(item.price) * entry.quantity; const itemTax = base * Number(item.gst_rate) / 100; subtotal += base; tax += itemTax;
      lines.push({ id: id(), sale_id: saleId, item_id: item.id, item_name: item.name, hsn_sac: item.hsn_sac, quantity: entry.quantity, unit_price: Number(item.price), gst_rate: Number(item.gst_rate), line_total: base + itemTax });
      await tx.query('UPDATE items SET stock=stock-?,updated_at=? WHERE id=?', [entry.quantity, created, item.id]);
    }
    sale = { id: saleId, invoice_no: invoiceNo, supply_type: body.supply_type, place_of_supply: body.place_of_supply, created_at: created, payment_mode: body.payment_mode, subtotal, tax, total: subtotal + tax, cashier_id: req.user.id, cashier_name: req.user.name, lines };
    await tx.query('INSERT INTO sales(id,invoice_no,supply_type,place_of_supply,created_at,payment_mode,subtotal,tax,total,cashier_id,cashier_name) VALUES(?,?,?,?,?,?,?,?,?,?,?)', [sale.id,sale.invoice_no,sale.supply_type,sale.place_of_supply,sale.created_at,sale.payment_mode,sale.subtotal,sale.tax,sale.total,sale.cashier_id,sale.cashier_name]);
    for (const line of lines) await tx.query('INSERT INTO sale_lines(id,sale_id,item_id,item_name,hsn_sac,quantity,unit_price,gst_rate,line_total) VALUES(?,?,?,?,?,?,?,?,?)', [line.id,line.sale_id,line.item_id,line.item_name,line.hsn_sac,line.quantity,line.unit_price,line.gst_rate,line.line_total]);
  });
  res.status(201).json(sale);
}));
app.get('/api/sales', allow('admin', 'cashier', 'viewer'), route(async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 50, 200);
  const { rows } = await db.query('SELECT * FROM sales ORDER BY created_at DESC LIMIT ?', [limit]); res.json(rows);
}));
app.get('/api/reports/summary', allow('admin', 'cashier', 'viewer'), route(async (_req, res) => {
  const today = db.dialect === 'postgres' ? 'created_at::date = CURRENT_DATE' : "date(created_at)=date('now','localtime')";
  const [{ rows: totals }, { rows: inventory }, { rows: recent }] = await Promise.all([
    db.query(`SELECT COUNT(*) AS sale_count, COALESCE(SUM(total),0) AS revenue, COALESCE(SUM(tax),0) AS tax FROM sales WHERE ${today}`),
    db.query('SELECT COUNT(*) AS item_count, COALESCE(SUM(stock*price),0) AS stock_value, SUM(CASE WHEN stock<=low_stock THEN 1 ELSE 0 END) AS low_stock_count FROM items'),
    db.query('SELECT id,created_at,total,payment_mode,cashier_name FROM sales ORDER BY created_at DESC LIMIT 6')
  ]);
  res.json({ ...totals[0], ...inventory[0], recent: recent });
}));
app.get('/api/shop', route(async (_req, res) => { const { rows } = await db.query('SELECT * FROM shop_profile WHERE id=1'); res.json(rows[0]); }));
app.put('/api/shop', allow('admin'), route(async (req, res) => {
  const shop = z.object({ name: z.string().trim().min(1), address: z.string(), phone: z.string(), gstin: z.string(), state: z.string().default(''), currency: z.string().length(3) }).parse(req.body);
  await db.query('UPDATE shop_profile SET name=?,address=?,phone=?,gstin=?,state=?,currency=? WHERE id=1', [shop.name,shop.address,shop.phone,shop.gstin,shop.state,shop.currency]); res.json(shop);
}));
app.get('/api/team', allow('admin'), (_req, res) => res.json({ message: 'Assign admin, cashier, or viewer custom claims in Firebase Admin. Invite users through Firebase Authentication.' }));

app.use((error, _req, res, _next) => {
  if (error instanceof z.ZodError) return res.status(400).json({ error: 'Invalid request', details: error.flatten() });
  if ((error.status || 500) >= 500) console.error(error);
  res.status(error.status || 500).json({ error: error.status ? error.message : 'Internal server error' });
});

const port = Number(process.env.PORT || 3000);
await db.init();
app.listen(port, () => console.log(`Ledgerly API listening on ${port} (${db.dialect})`));
