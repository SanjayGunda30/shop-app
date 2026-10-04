import Database from 'better-sqlite3';
import pg from 'pg';
import 'dotenv/config';

const schema = `
CREATE TABLE IF NOT EXISTS items (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, sku TEXT NOT NULL UNIQUE,
  price REAL NOT NULL CHECK(price >= 0), unit TEXT NOT NULL DEFAULT 'each',
  stock REAL NOT NULL DEFAULT 0 CHECK(stock >= 0), low_stock REAL NOT NULL DEFAULT 5,
  image_url TEXT, gst_rate REAL NOT NULL DEFAULT 0, hsn_sac TEXT NOT NULL DEFAULT '', updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sales (
  id TEXT PRIMARY KEY, invoice_no TEXT NOT NULL UNIQUE, supply_type TEXT NOT NULL DEFAULT 'intra_state', place_of_supply TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, payment_mode TEXT NOT NULL,
  subtotal REAL NOT NULL, tax REAL NOT NULL, total REAL NOT NULL,
  cashier_id TEXT NOT NULL, cashier_name TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sale_lines (
  id TEXT PRIMARY KEY, sale_id TEXT NOT NULL REFERENCES sales(id), item_id TEXT NOT NULL,
  item_name TEXT NOT NULL, hsn_sac TEXT NOT NULL DEFAULT '', quantity REAL NOT NULL, unit_price REAL NOT NULL,
  gst_rate REAL NOT NULL, line_total REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS shop_profile (
  id INTEGER PRIMARY KEY, name TEXT NOT NULL, address TEXT NOT NULL,
  phone TEXT NOT NULL, gstin TEXT NOT NULL, state TEXT NOT NULL DEFAULT '', currency TEXT NOT NULL DEFAULT 'INR'
);
CREATE TABLE IF NOT EXISTS invoice_sequence (id INTEGER PRIMARY KEY, value INTEGER NOT NULL);
`;
const migrations = [
  ['items', 'hsn_sac', "TEXT NOT NULL DEFAULT ''"],
  ['sales', 'invoice_no', "TEXT NOT NULL DEFAULT ''"],
  ['sales', 'supply_type', "TEXT NOT NULL DEFAULT 'intra_state'"],
  ['sales', 'place_of_supply', "TEXT NOT NULL DEFAULT ''"],
  ['sale_lines', 'hsn_sac', "TEXT NOT NULL DEFAULT ''"],
  ['shop_profile', 'state', "TEXT NOT NULL DEFAULT ''"],
];
const returnsRows = (sql) => /^\s*(SELECT|PRAGMA)/i.test(sql) || /\bRETURNING\b/i.test(sql);

const usePostgres = Boolean(process.env.DATABASE_URL);
let db;
if (usePostgres) {
  const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.DATABASE_SSL === 'false' ? false : { rejectUnauthorized: false } });
  const translate = (sql) => {
    let index = 0;
    return sql.replace(/\?/g, () => `$${++index}`).replace(/REAL/g, 'DOUBLE PRECISION').replace(/TEXT PRIMARY KEY/g, 'TEXT PRIMARY KEY');
  };
  const exec = async (sql) => {
    for (const statement of sql.split(';').map((part) => part.trim()).filter(Boolean)) await pool.query(translate(statement));
  };
  db = {
    dialect: 'postgres',
    query: async (sql, params = []) => {
      const result = await pool.query(translate(sql), params);
      return { rows: result.rows, changes: result.rowCount };
    },
    init: async () => {
      await exec(schema);
      for (const [table, column, definition] of migrations) await pool.query(`ALTER TABLE ${table} ADD COLUMN IF NOT EXISTS ${column} ${definition}`);
      await pool.query("CREATE UNIQUE INDEX IF NOT EXISTS sales_invoice_no_unique ON sales(invoice_no) WHERE invoice_no <> ''");
      const found = await pool.query('SELECT id FROM shop_profile WHERE id = 1');
      if (!found.rowCount) await pool.query("INSERT INTO shop_profile(id,name,address,phone,gstin,state,currency) VALUES(1,'Your Shop','Add your address','+91 00000 00000','','','INR')");
      await pool.query('INSERT INTO invoice_sequence(id,value) VALUES(1,0) ON CONFLICT (id) DO NOTHING');
    },
    transaction: async (work) => {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const tx = { query: async (sql, params = []) => { const result = await client.query(translate(sql), params); return { rows: result.rows, changes: result.rowCount }; } };
        const result = await work(tx);
        await client.query('COMMIT');
        return result;
      } catch (error) { await client.query('ROLLBACK'); throw error; }
      finally { client.release(); }
    }
  };
} else {
  const sqlite = new Database(process.env.SQLITE_PATH || './ledgerly.sqlite');
  sqlite.pragma('journal_mode = WAL');
  db = {
    dialect: 'sqlite',
    query: async (sql, params = []) => {
      const statement = sqlite.prepare(sql);
      if (returnsRows(sql)) return { rows: statement.all(...params), changes: 0 };
      const result = statement.run(...params);
      return { rows: [], changes: result.changes, lastInsertRowid: result.lastInsertRowid };
    },
    init: async () => {
      sqlite.exec(schema);
      for (const [table, column, definition] of migrations) {
        const columns = sqlite.pragma(`table_info(${table})`).map((entry) => entry.name);
        if (!columns.includes(column)) sqlite.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
      }
      sqlite.exec("CREATE UNIQUE INDEX IF NOT EXISTS sales_invoice_no_unique ON sales(invoice_no) WHERE invoice_no <> ''");
      sqlite.prepare("INSERT OR IGNORE INTO shop_profile(id,name,address,phone,gstin,state,currency) VALUES(1,'Your Shop','Add your address','+91 00000 00000','','','INR')").run();
      sqlite.prepare('INSERT OR IGNORE INTO invoice_sequence(id,value) VALUES(1,0)').run();
    },
    transaction: async (work) => {
      sqlite.exec('BEGIN IMMEDIATE');
      try {
        const result = await work({
        query: async (sql, params = []) => {
          const statement = sqlite.prepare(sql);
          if (returnsRows(sql)) return { rows: statement.all(...params), changes: 0 };
          const result = statement.run(...params);
          return { rows: [], changes: result.changes, lastInsertRowid: result.lastInsertRowid };
        }
        });
        sqlite.exec('COMMIT');
        return result;
      } catch (error) {
        sqlite.exec('ROLLBACK');
        throw error;
      }
    }
  };
}

export default db;
