import { Router, Request, Response } from "express";
import { getDb } from "../db";
import type { ProposalRow, SignatureRow } from "../types";

const router = Router();

/**
 * GET /api/proposals
 * Query params: ?status=Pending|Executed|Expired  &treasury_id=0x...  &limit=50  &offset=0
 */
router.get("/", (req: Request, res: Response) => {
  try {
    const db = getDb();
    const conditions: string[] = [];
    const params: unknown[] = [];

    if (req.query.status) {
      conditions.push("status = ?");
      params.push(req.query.status);
    }
    if (req.query.treasury_id) {
      conditions.push("treasury_id = ?");
      params.push(req.query.treasury_id);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const offset = Number(req.query.offset) || 0;

    const rows = db
      .prepare(
        `SELECT * FROM proposals ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`
      )
      .all(...params, limit, offset) as ProposalRow[];

    const countRow = db
      .prepare(`SELECT COUNT(*) as total FROM proposals ${where}`)
      .get(...params) as { total: number };

    res.json({
      data: rows,
      total: countRow.total,
      limit,
      offset,
    });
  } catch (err) {
    console.error("[proposals] Error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * GET /api/proposals/:id
 * Returns the proposal with its signatures.
 */
router.get("/:id", (req: Request, res: Response) => {
  try {
    const db = getDb();
    const proposal = db
      .prepare("SELECT * FROM proposals WHERE id = ?")
      .get(req.params.id) as ProposalRow | undefined;

    if (!proposal) {
      res.status(404).json({ error: "Proposal not found" });
      return;
    }

    const signatures = db
      .prepare("SELECT * FROM signatures WHERE proposal_id = ? ORDER BY signed_at ASC")
      .all(req.params.id) as SignatureRow[];

    res.json({ ...proposal, signatures });
  } catch (err) {
    console.error("[proposals] Error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
