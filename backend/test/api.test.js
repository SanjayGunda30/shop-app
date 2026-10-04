import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import Database from 'better-sqlite3';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const backendDir = resolve(import.meta.dirname, '..');
const port = 43187;
const base = `http://127.0.0.1:${port}`;
const headers = (role) => ({ 'content-type': 'application/json', 'x-demo-role': role });

async function waitForApi(child) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (child.exitCode !== null) throw new Error('API exited before startup');
    try { const response = await fetch(`${base}/api/health`); if (response.ok) return; } catch {}
    await new Promise((resolveDelay) => setTimeout(resolveDelay, 100));
  }
  throw new Error('API did not start in time');
}

test('roles, stock-safe checkout, and reports work together', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'ledgerly-api-'));
  const databasePath = join(directory, 'test.sqlite');
  const legacy = new Database(databasePath);
  legacy.exec(`
    CREATE TABLE items (id TEXT PRIMARY KEY, name TEXT NOT NULL, sku TEXT NOT NULL UNIQUE, price REAL NOT NULL, unit TEXT NOT NULL DEFAULT 'each', stock REAL NOT NULL DEFAULT 0, low_stock REAL NOT NULL DEFAULT 5, image_url TEXT, gst_rate REAL NOT NULL DEFAULT 0, updated_at TEXT NOT NULL);
    CREATE TABLE sales (id TEXT PRIMARY KEY, created_at TEXT NOT NULL, payment_mode TEXT NOT NULL, subtotal REAL NOT NULL, tax REAL NOT NULL, total REAL NOT NULL, cashier_id TEXT NOT NULL, cashier_name TEXT NOT NULL);
    CREATE TABLE sale_lines (id TEXT PRIMARY KEY, sale_id TEXT NOT NULL, item_id TEXT NOT NULL, item_name TEXT NOT NULL, quantity REAL NOT NULL, unit_price REAL NOT NULL, gst_rate REAL NOT NULL, line_total REAL NOT NULL);
    CREATE TABLE shop_profile (id INTEGER PRIMARY KEY, name TEXT NOT NULL, address TEXT NOT NULL, phone TEXT NOT NULL, gstin TEXT NOT NULL, currency TEXT NOT NULL DEFAULT 'INR');
    INSERT INTO shop_profile(id,name,address,phone,gstin,currency) VALUES(1,'Existing Shop','Old address','+91 00000 00000','','INR');
  `);
  legacy.close();
  const child = spawn(process.execPath, ['src/server.js'], { cwd: backendDir, env: { ...process.env, PORT: `${port}`, NODE_ENV: 'development', SQLITE_PATH: databasePath, DATABASE_URL: '', FIREBASE_SERVICE_ACCOUNT: '' }, stdio: 'inherit' });
  try {
    await waitForApi(child);
    const unauthorized = await fetch(`${base}/api/items`);
    assert.equal(unauthorized.status, 401);

    const created = await fetch(`${base}/api/items`, { method: 'POST', headers: headers('admin'), body: JSON.stringify({ name: 'Test tea', sku: 'TEST-TEA', price: 100, unit: 'cup', stock: 2, gst_rate: 5, hsn_sac: '0902' }) });
    assert.equal(created.status, 201);
    const item = await created.json();

    const forbidden = await fetch(`${base}/api/items`, { method: 'POST', headers: headers('cashier'), body: JSON.stringify({ name: 'Denied', sku: 'DENIED', price: 1, unit: 'each', stock: 1 }) });
    assert.equal(forbidden.status, 403);

    const rejected = await fetch(`${base}/api/sales`, { method: 'POST', headers: headers('cashier'), body: JSON.stringify({ payment_mode: 'Cash', lines: [{ item_id: item.id, quantity: 3 }] }) });
    assert.equal(rejected.status, 409);
    const afterRejected = await (await fetch(`${base}/api/items`, { headers: headers('viewer') })).json();
    assert.equal(afterRejected[0].stock, 2);

    const completed = await fetch(`${base}/api/sales`, { method: 'POST', headers: headers('cashier'), body: JSON.stringify({ payment_mode: 'UPI', supply_type: 'inter_state', place_of_supply: 'Tamil Nadu', lines: [{ item_id: item.id, quantity: 1 }] }) });
    assert.equal(completed.status, 201);
    const sale = await completed.json();
    assert.equal(sale.total, 105);
    assert.equal(sale.supply_type, 'inter_state');
    assert.equal(sale.place_of_supply, 'Tamil Nadu');
    assert.match(sale.invoice_no, /^INV\/\d{2}-\d{2}\/00001$/);
    assert.equal(sale.lines[0].hsn_sac, '0902');
    const remaining = await (await fetch(`${base}/api/items`, { headers: headers('viewer') })).json();
    assert.equal(remaining[0].stock, 1);
    const second = await fetch(`${base}/api/sales`, { method: 'POST', headers: headers('cashier'), body: JSON.stringify({ payment_mode: 'Cash', lines: [{ item_id: item.id, quantity: 1 }] }) });
    assert.equal((await second.json()).invoice_no, sale.invoice_no.replace('00001', '00002'));
    const report = await fetch(`${base}/api/reports/summary`, { headers: headers('viewer') });
    assert.equal(report.status, 200);
    assert.equal((await report.json()).sale_count, 2);
  } finally {
    if (child.exitCode === null) {
      const exited = new Promise((resolveExit) => child.once('exit', resolveExit));
      child.kill();
      await exited;
    }
    rmSync(directory, { recursive: true, force: true });
  }
});
