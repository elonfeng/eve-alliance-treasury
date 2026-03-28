import express from "express";
import cors from "cors";
import { config } from "./config";
import { getDb } from "./db";
import { startIndexer } from "./indexer";
import healthRouter from "./routes/health";
import proposalsRouter from "./routes/proposals";
import auditRouter from "./routes/audit";
import killmailsRouter from "./routes/killmails";
import agentRouter from "./routes/agent";

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// Routes
app.use("/api/health", healthRouter);
app.use("/api/proposals", proposalsRouter);
app.use("/api/audit", auditRouter);
app.use("/api/killmails", killmailsRouter);
app.use("/api/agent", agentRouter);

// Initialize DB eagerly so tables exist before any request
getDb();

// Start the event indexer
startIndexer();

app.listen(config.port, () => {
  console.log(`[server] Alliance Treasury API running on http://localhost:${config.port}`);
});
