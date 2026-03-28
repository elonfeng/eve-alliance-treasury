import { Router, Request, Response } from "express";
import { getDb } from "../db";
import type { KillmailRow } from "../types";

const router = Router();

/**
 * GET /api/killmails
 * Query params: ?killer_id=0x...  &victim_id=0x...  &limit=50  &offset=0
 */
router.get("/", (req: Request, res: Response) => {
  try {
    const db = getDb();
    const conditions: string[] = [];
    const params: unknown[] = [];

    if (req.query.killer_id) {
      conditions.push("killer_id = ?");
      params.push(req.query.killer_id);
    }
    if (req.query.victim_id) {
      conditions.push("victim_id = ?");
      params.push(req.query.victim_id);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const offset = Number(req.query.offset) || 0;

    const rows = db
      .prepare(
        `SELECT * FROM killmails ${where} ORDER BY kill_timestamp DESC LIMIT ? OFFSET ?`
      )
      .all(...params, limit, offset) as KillmailRow[];

    const countRow = db
      .prepare(`SELECT COUNT(*) as total FROM killmails ${where}`)
      .get(...params) as { total: number };

    res.json({
      data: rows,
      total: countRow.total,
      limit,
      offset,
    });
  } catch (err) {
    console.error("[killmails] Error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
