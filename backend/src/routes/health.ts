import { Router, Request, Response } from "express";
import { getDb } from "../db";

const router = Router();

router.get("/", (_req: Request, res: Response) => {
  try {
    const db = getDb();
    // Quick sanity check
    const row = db.prepare("SELECT COUNT(*) as count FROM proposals").get() as {
      count: number;
    };

    res.json({
      status: "ok",
      timestamp: new Date().toISOString(),
      proposals_indexed: row.count,
    });
  } catch (err) {
    res.status(500).json({
      status: "error",
      message: err instanceof Error ? err.message : "Unknown error",
    });
  }
});

export default router;
