import { Router, Request, Response } from "express";
import { getDb } from "../db";

const router = Router();

/**
 * GET /api/agent/stats
 * Aggregated stats: total proposals, payouts, signatures by agent, killmails, jumps.
 */
router.get("/stats", (_req: Request, res: Response) => {
  try {
    const db = getDb();

    const proposalStats = db
      .prepare(
        `SELECT
           COUNT(*) as total,
           SUM(CASE WHEN status = 'Pending' THEN 1 ELSE 0 END) as pending,
           SUM(CASE WHEN status = 'Executed' THEN 1 ELSE 0 END) as executed,
           SUM(CASE WHEN status = 'Expired' THEN 1 ELSE 0 END) as expired
         FROM proposals`
      )
      .get() as {
      total: number;
      pending: number;
      executed: number;
      expired: number;
    };

    const payoutStats = db
      .prepare(
        `SELECT
           COUNT(*) as total_payouts,
           COALESCE(SUM(CAST(amount AS INTEGER)), 0) as total_amount
         FROM payouts`
      )
      .get() as { total_payouts: number; total_amount: number };

    const signatureCount = db
      .prepare("SELECT COUNT(*) as total FROM signatures")
      .get() as { total: number };

    const killmailCount = db
      .prepare("SELECT COUNT(*) as total FROM killmails")
      .get() as { total: number };

    const jumpCount = db
      .prepare("SELECT COUNT(*) as total FROM jumps")
      .get() as { total: number };

    res.json({
      proposals: proposalStats,
      payouts: {
        count: payoutStats.total_payouts,
        total_amount_mist: payoutStats.total_amount.toString(),
      },
      signatures: signatureCount.total,
      killmails: killmailCount.total,
      jumps: jumpCount.total,
    });
  } catch (err) {
    console.error("[agent] Error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
