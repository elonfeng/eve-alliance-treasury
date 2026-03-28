import { Router, Request, Response } from "express";
import { getDb } from "../db";
import type { PayoutRow } from "../types";

const router = Router();

/**
 * GET /api/audit
 * Returns all payouts (PaidOut + ProposalExecuted events combined into the payouts table).
 * Query params: ?treasury_id=0x...  &limit=50  &offset=0
 */
router.get("/", (req: Request, res: Response) => {
  try {
    const db = getDb();
    const conditions: string[] = [];
    const params: unknown[] = [];

    if (req.query.treasury_id) {
      conditions.push("p.treasury_id = ?");
      params.push(req.query.treasury_id);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const offset = Number(req.query.offset) || 0;

    const rows = db
      .prepare(
        `SELECT p.*, pr.purpose, pr.proposer
         FROM payouts p
         LEFT JOIN proposals pr ON pr.id = p.proposal_id
         ${where}
         ORDER BY p.executed_at DESC
         LIMIT ? OFFSET ?`
      )
      .all(...params, limit, offset) as (PayoutRow & {
      purpose?: string;
      proposer?: string;
    })[];

    const countRow = db
      .prepare(`SELECT COUNT(*) as total FROM payouts p ${where}`)
      .get(...params) as { total: number };

    res.json({
      data: rows,
      total: countRow.total,
      limit,
      offset,
    });
  } catch (err) {
    console.error("[audit] Error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
