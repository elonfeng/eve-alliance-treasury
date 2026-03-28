import Database from "better-sqlite3";
import path from "path";

const DB_PATH = path.resolve(__dirname, "..", "data", "treasury.db");

let db: Database.Database;

export function getDb(): Database.Database {
  if (!db) {
    // Ensure data directory exists
    const fs = require("fs");
    const dir = path.dirname(DB_PATH);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    db = new Database(DB_PATH);
    db.pragma("journal_mode = WAL");
    db.pragma("foreign_keys = ON");
    initTables(db);
  }
  return db;
}

function initTables(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS proposals (
      id              TEXT PRIMARY KEY,
      treasury_id     TEXT NOT NULL,
      proposer        TEXT NOT NULL,
      amount          TEXT NOT NULL,
      recipient       TEXT NOT NULL,
      purpose         TEXT NOT NULL DEFAULT '',
      required_sigs   INTEGER NOT NULL,
      status          TEXT NOT NULL DEFAULT 'Pending',
      created_at      TEXT NOT NULL,
      expires_at      TEXT NOT NULL DEFAULT ''
    );

    CREATE TABLE IF NOT EXISTS signatures (
      proposal_id     TEXT NOT NULL,
      signer          TEXT NOT NULL,
      signed_at       TEXT NOT NULL,
      PRIMARY KEY (proposal_id, signer)
    );

    CREATE TABLE IF NOT EXISTS payouts (
      proposal_id     TEXT NOT NULL,
      treasury_id     TEXT NOT NULL,
      recipient       TEXT NOT NULL,
      amount          TEXT NOT NULL,
      executor        TEXT NOT NULL,
      executed_at     TEXT NOT NULL,
      PRIMARY KEY (proposal_id)
    );

    CREATE TABLE IF NOT EXISTS killmails (
      id              TEXT PRIMARY KEY,
      killer_id       TEXT NOT NULL,
      victim_id       TEXT NOT NULL,
      loss_type       TEXT NOT NULL DEFAULT '',
      solar_system_id TEXT NOT NULL DEFAULT '',
      kill_timestamp  TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS jumps (
      source_gate_id  TEXT NOT NULL,
      dest_gate_id    TEXT NOT NULL,
      character_id    TEXT NOT NULL,
      timestamp       TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS cursors (
      key             TEXT PRIMARY KEY,
      tx_digest       TEXT NOT NULL,
      event_seq       TEXT NOT NULL
    );
  `);
}
