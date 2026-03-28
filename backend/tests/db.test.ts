import { describe, it, expect, beforeEach } from "vitest";
import { initDb, getDb } from "../src/db";
import Database from "better-sqlite3";

describe("Database", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = initDb(":memory:");
  });

  it("creates all expected tables", () => {
    const tables = db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
      )
      .all() as { name: string }[];
    const names = tables.map((t) => t.name);
    expect(names).toContain("proposals");
    expect(names).toContain("signatures");
    expect(names).toContain("payouts");
    expect(names).toContain("killmails");
    expect(names).toContain("jumps");
    expect(names).toContain("cursors");
  });

  it("inserts and queries a proposal", () => {
    db.prepare(
      `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?, ?)`
    ).run("p1", "t1", "0xAlice", "1000", "0xBob", "test payout", 2, "2025-01-01T00:00:00Z", "2025-02-01T00:00:00Z");

    const row = db.prepare("SELECT * FROM proposals WHERE id = ?").get("p1") as any;
    expect(row).toBeDefined();
    expect(row.id).toBe("p1");
    expect(row.proposer).toBe("0xAlice");
    expect(row.amount).toBe("1000");
    expect(row.status).toBe("Pending");
  });

  it("inserts a signature with foreign key to proposal", () => {
    db.prepare(
      `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?)`
    ).run("p1", "t1", "0xAlice", "1000", "0xBob", "test", 2, "2025-01-01T00:00:00Z");

    db.prepare(
      `INSERT INTO signatures (proposal_id, signer, signed_at) VALUES (?, ?, ?)`
    ).run("p1", "0xAlice", "2025-01-01T00:00:00Z");

    const sigs = db.prepare("SELECT * FROM signatures WHERE proposal_id = ?").all("p1") as any[];
    expect(sigs).toHaveLength(1);
    expect(sigs[0].signer).toBe("0xAlice");
  });

  it("inserts and queries a payout", () => {
    db.prepare(
      `INSERT INTO payouts (proposal_id, treasury_id, recipient, amount, executor, executed_at)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).run("p1", "t1", "0xBob", "1000", "0xAlice", "2025-01-02T00:00:00Z");

    const row = db.prepare("SELECT * FROM payouts WHERE proposal_id = ?").get("p1") as any;
    expect(row).toBeDefined();
    expect(row.recipient).toBe("0xBob");
    expect(row.amount).toBe("1000");
  });

  it("reads and writes cursors", () => {
    // Initially empty
    const empty = db.prepare("SELECT * FROM cursors WHERE key = ?").get("test") as any;
    expect(empty).toBeUndefined();

    // Insert
    db.prepare(
      `INSERT INTO cursors (key, tx_digest, event_seq) VALUES (?, ?, ?)`
    ).run("test", "digest1", "0");

    const row = db.prepare("SELECT * FROM cursors WHERE key = ?").get("test") as any;
    expect(row.tx_digest).toBe("digest1");
    expect(row.event_seq).toBe("0");

    // Update
    db.prepare(
      `INSERT INTO cursors (key, tx_digest, event_seq) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET tx_digest = excluded.tx_digest, event_seq = excluded.event_seq`
    ).run("test", "digest2", "5");

    const updated = db.prepare("SELECT * FROM cursors WHERE key = ?").get("test") as any;
    expect(updated.tx_digest).toBe("digest2");
    expect(updated.event_seq).toBe("5");
  });
});
