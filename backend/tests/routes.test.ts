import { describe, it, expect, beforeEach, vi, beforeAll, afterAll } from "vitest";
import { initDb, getDb } from "../src/db";
import Database from "better-sqlite3";

// Initialize in-memory DB before importing the app so that getDb() and
// startIndexer() use the in-memory instance.
// We also mock the indexer to prevent it from polling real Sui RPCs.
vi.mock("../src/indexer", () => ({
  startIndexer: vi.fn(),
}));

import request from "supertest";
import { app } from "../src/index";

describe("Routes", () => {
  let db: Database.Database;

  beforeEach(() => {
    db = initDb(":memory:");
  });

  // ---------- /api/health ----------

  describe("GET /api/health", () => {
    it("returns 200 with status ok", async () => {
      const res = await request(app).get("/api/health");
      expect(res.status).toBe(200);
      expect(res.body.status).toBe("ok");
    });

    it("includes proposal count", async () => {
      db.prepare(
        `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?)`
      ).run("p1", "t1", "0xA", "100", "0xB", "test", 2, "2025-01-01T00:00:00Z");

      const res = await request(app).get("/api/health");
      expect(res.status).toBe(200);
      expect(res.body.proposals_indexed).toBe(1);
    });
  });

  // ---------- /api/proposals ----------

  describe("GET /api/proposals", () => {
    it("returns empty array when no proposals", async () => {
      const res = await request(app).get("/api/proposals");
      expect(res.status).toBe(200);
      expect(res.body.data).toEqual([]);
      expect(res.body.total).toBe(0);
    });

    it("returns proposals after inserting test data", async () => {
      db.prepare(
        `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?, ?)`
      ).run("p1", "t1", "0xA", "100", "0xB", "test", 2, "2025-01-01T00:00:00Z", "2025-02-01T00:00:00Z");

      const res = await request(app).get("/api/proposals");
      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].id).toBe("p1");
      expect(res.body.total).toBe(1);
    });

    it("supports ?limit parameter", async () => {
      for (let i = 0; i < 5; i++) {
        db.prepare(
          `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?)`
        ).run(`p${i}`, "t1", "0xA", "100", "0xB", "test", 2, `2025-01-0${i + 1}T00:00:00Z`);
      }

      const res = await request(app).get("/api/proposals?limit=2");
      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(2);
      expect(res.body.total).toBe(5);
      expect(res.body.limit).toBe(2);
    });

    it("supports ?status filter", async () => {
      db.prepare(
        `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).run("p1", "t1", "0xA", "100", "0xB", "test", 2, "Pending", "2025-01-01T00:00:00Z");
      db.prepare(
        `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
      ).run("p2", "t1", "0xA", "200", "0xB", "test2", 2, "Executed", "2025-01-02T00:00:00Z");

      const res = await request(app).get("/api/proposals?status=Pending");
      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].id).toBe("p1");
    });

    it("GET /api/proposals/:id returns proposal with signatures", async () => {
      db.prepare(
        `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?)`
      ).run("p1", "t1", "0xA", "100", "0xB", "test", 2, "2025-01-01T00:00:00Z");
      db.prepare(
        `INSERT INTO signatures (proposal_id, signer, signed_at) VALUES (?, ?, ?)`
      ).run("p1", "0xA", "2025-01-01T00:00:00Z");
      db.prepare(
        `INSERT INTO signatures (proposal_id, signer, signed_at) VALUES (?, ?, ?)`
      ).run("p1", "0xC", "2025-01-01T01:00:00Z");

      const res = await request(app).get("/api/proposals/p1");
      expect(res.status).toBe(200);
      expect(res.body.id).toBe("p1");
      expect(res.body.signatures).toHaveLength(2);
      expect(res.body.signatures[0].signer).toBe("0xA");
    });

    it("GET /api/proposals/:id returns 404 for missing proposal", async () => {
      const res = await request(app).get("/api/proposals/nonexistent");
      expect(res.status).toBe(404);
    });
  });

  // ---------- /api/audit ----------

  describe("GET /api/audit", () => {
    it("returns empty array when no payouts", async () => {
      const res = await request(app).get("/api/audit");
      expect(res.status).toBe(200);
      expect(res.body.data).toEqual([]);
      expect(res.body.total).toBe(0);
    });

    it("returns audit entries after inserting test data", async () => {
      db.prepare(
        `INSERT INTO payouts (proposal_id, treasury_id, recipient, amount, executor, executed_at)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run("p1", "t1", "0xB", "1000", "0xA", "2025-01-01T00:00:00Z");

      const res = await request(app).get("/api/audit");
      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].proposal_id).toBe("p1");
    });

    it("supports ?limit parameter", async () => {
      for (let i = 0; i < 5; i++) {
        db.prepare(
          `INSERT INTO payouts (proposal_id, treasury_id, recipient, amount, executor, executed_at)
           VALUES (?, ?, ?, ?, ?, ?)`
        ).run(`p${i}`, "t1", "0xB", "1000", "0xA", `2025-01-0${i + 1}T00:00:00Z`);
      }

      const res = await request(app).get("/api/audit?limit=3");
      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(3);
      expect(res.body.total).toBe(5);
      expect(res.body.limit).toBe(3);
    });
  });

  // ---------- /api/killmails ----------

  describe("GET /api/killmails", () => {
    it("returns empty array when no killmails", async () => {
      const res = await request(app).get("/api/killmails");
      expect(res.status).toBe(200);
      expect(res.body.data).toEqual([]);
      expect(res.body.total).toBe(0);
    });

    it("returns killmails after inserting", async () => {
      db.prepare(
        `INSERT INTO killmails (id, killer_id, victim_id, loss_type, solar_system_id, kill_timestamp)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run("k1", "0xKiller", "0xVictim", "ship", "sol1", "2025-01-01T00:00:00Z");

      const res = await request(app).get("/api/killmails");
      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].id).toBe("k1");
    });

    it("supports ?killer_id filter", async () => {
      db.prepare(
        `INSERT INTO killmails (id, killer_id, victim_id, loss_type, solar_system_id, kill_timestamp)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run("k1", "0xKiller1", "0xVictim", "ship", "sol1", "2025-01-01T00:00:00Z");
      db.prepare(
        `INSERT INTO killmails (id, killer_id, victim_id, loss_type, solar_system_id, kill_timestamp)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run("k2", "0xKiller2", "0xVictim", "ship", "sol1", "2025-01-02T00:00:00Z");

      const res = await request(app).get("/api/killmails?killer_id=0xKiller1");
      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].killer_id).toBe("0xKiller1");
    });

    it("supports ?victim_id filter", async () => {
      db.prepare(
        `INSERT INTO killmails (id, killer_id, victim_id, loss_type, solar_system_id, kill_timestamp)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run("k1", "0xKiller", "0xVictim1", "ship", "sol1", "2025-01-01T00:00:00Z");
      db.prepare(
        `INSERT INTO killmails (id, killer_id, victim_id, loss_type, solar_system_id, kill_timestamp)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run("k2", "0xKiller", "0xVictim2", "ship", "sol1", "2025-01-02T00:00:00Z");

      const res = await request(app).get("/api/killmails?victim_id=0xVictim2");
      expect(res.status).toBe(200);
      expect(res.body.data).toHaveLength(1);
      expect(res.body.data[0].victim_id).toBe("0xVictim2");
    });
  });

  // ---------- /api/agent/stats ----------

  describe("GET /api/agent/stats", () => {
    it("returns zeroed stats when empty", async () => {
      const res = await request(app).get("/api/agent/stats");
      expect(res.status).toBe(200);
      expect(res.body.proposals.total).toBe(0);
      expect(res.body.payouts.count).toBe(0);
      expect(res.body.signatures).toBe(0);
      expect(res.body.killmails).toBe(0);
      expect(res.body.jumps).toBe(0);
    });

    it("returns correct counts after inserting data", async () => {
      // Insert proposal
      db.prepare(
        `INSERT INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?)`
      ).run("p1", "t1", "0xA", "100", "0xB", "test", 2, "2025-01-01T00:00:00Z");

      // Insert signature
      db.prepare(
        `INSERT INTO signatures (proposal_id, signer, signed_at) VALUES (?, ?, ?)`
      ).run("p1", "0xA", "2025-01-01T00:00:00Z");

      // Insert payout
      db.prepare(
        `INSERT INTO payouts (proposal_id, treasury_id, recipient, amount, executor, executed_at)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run("p1", "t1", "0xB", "5000", "0xA", "2025-01-02T00:00:00Z");

      // Insert killmail
      db.prepare(
        `INSERT INTO killmails (id, killer_id, victim_id, loss_type, solar_system_id, kill_timestamp)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run("k1", "0xK", "0xV", "ship", "sol1", "2025-01-01T00:00:00Z");

      // Insert jump
      db.prepare(
        `INSERT INTO jumps (source_gate_id, dest_gate_id, character_id, timestamp)
         VALUES (?, ?, ?, ?)`
      ).run("g1", "g2", "0xC", "2025-01-01T00:00:00Z");

      const res = await request(app).get("/api/agent/stats");
      expect(res.status).toBe(200);
      expect(res.body.proposals.total).toBe(1);
      expect(res.body.proposals.pending).toBe(1);
      expect(res.body.payouts.count).toBe(1);
      expect(res.body.payouts.total_amount_mist).toBe("5000");
      expect(res.body.signatures).toBe(1);
      expect(res.body.killmails).toBe(1);
      expect(res.body.jumps).toBe(1);
    });
  });
});
