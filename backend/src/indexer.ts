import { SuiClient, SuiEvent, SuiEventFilter, EventId } from "@mysten/sui/client";
import { config } from "./config";
import { getDb } from "./db";
import type {
  ProposalCreatedEvent,
  ProposalSignedEvent,
  ProposalExecutedEvent,
  ProposalMarkedExpiredEvent,
  AgentAutoSignedEvent,
  PaidOutEvent,
  KillmailCreatedEvent,
  JumpEventData,
} from "./types";

const TREASURY_POLL_MS = 10_000;
const EVE_POLL_MS = 30_000;
const PAGE_LIMIT = 50;

let client: SuiClient;

function getClient(): SuiClient {
  if (!client) {
    client = new SuiClient({ url: config.suiRpcUrl });
  }
  return client;
}

// ---- Cursor helpers ----

function loadCursor(key: string): EventId | null {
  const db = getDb();
  const row = db
    .prepare("SELECT tx_digest, event_seq FROM cursors WHERE key = ?")
    .get(key) as { tx_digest: string; event_seq: string } | undefined;
  if (!row) return null;
  return { txDigest: row.tx_digest, eventSeq: row.event_seq };
}

function saveCursor(key: string, cursor: EventId): void {
  const db = getDb();
  db.prepare(
    `INSERT INTO cursors (key, tx_digest, event_seq)
     VALUES (?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET tx_digest = excluded.tx_digest, event_seq = excluded.event_seq`
  ).run(key, cursor.txDigest, cursor.eventSeq);
}

// ---- Event processors ----

function processProposalCreated(evt: ProposalCreatedEvent, timestamp: string): void {
  const db = getDb();
  db.prepare(
    `INSERT OR IGNORE INTO proposals (id, treasury_id, proposer, amount, recipient, purpose, required_sigs, status, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'Pending', ?, ?)`
  ).run(
    evt.proposal_id,
    evt.treasury_id,
    evt.proposer,
    evt.amount,
    evt.recipient,
    evt.purpose,
    Number(evt.required_count),
    timestamp,
    evt.expires_at
  );

  // Proposer auto-signs
  db.prepare(
    `INSERT OR IGNORE INTO signatures (proposal_id, signer, signed_at)
     VALUES (?, ?, ?)`
  ).run(evt.proposal_id, evt.proposer, timestamp);
}

function processProposalSigned(evt: ProposalSignedEvent, timestamp: string): void {
  const db = getDb();
  db.prepare(
    `INSERT OR IGNORE INTO signatures (proposal_id, signer, signed_at)
     VALUES (?, ?, ?)`
  ).run(evt.proposal_id, evt.signer, timestamp);
}

function processAgentAutoSigned(evt: AgentAutoSignedEvent, timestamp: string): void {
  const db = getDb();
  db.prepare(
    `INSERT OR IGNORE INTO signatures (proposal_id, signer, signed_at)
     VALUES (?, ?, ?)`
  ).run(evt.proposal_id, evt.agent_id, timestamp);
}

function processProposalExecuted(evt: ProposalExecutedEvent, timestamp: string): void {
  const db = getDb();
  db.prepare(`UPDATE proposals SET status = 'Executed' WHERE id = ?`).run(
    evt.proposal_id
  );
  db.prepare(
    `INSERT OR IGNORE INTO payouts (proposal_id, treasury_id, recipient, amount, executor, executed_at)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(
    evt.proposal_id,
    evt.treasury_id,
    evt.recipient,
    evt.amount,
    evt.executor,
    timestamp
  );
}

function processProposalMarkedExpired(evt: ProposalMarkedExpiredEvent): void {
  const db = getDb();
  db.prepare(`UPDATE proposals SET status = 'Expired' WHERE id = ?`).run(
    evt.proposal_id
  );
}

function processPaidOut(evt: PaidOutEvent, timestamp: string): void {
  const db = getDb();
  // PaidOut is emitted by treasury::payout alongside ProposalExecuted.
  // We already store payout in processProposalExecuted, but this ensures
  // coverage if PaidOut arrives first or alone.
  db.prepare(
    `INSERT OR IGNORE INTO payouts (proposal_id, treasury_id, recipient, amount, executor, executed_at)
     VALUES (?, ?, ?, ?, '', ?)`
  ).run(evt.proposal_id, evt.treasury_id, evt.recipient, evt.amount, timestamp);
}

function processKillmail(evt: KillmailCreatedEvent): void {
  const db = getDb();
  db.prepare(
    `INSERT OR IGNORE INTO killmails (id, killer_id, victim_id, loss_type, solar_system_id, kill_timestamp)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(
    evt.id,
    evt.killer_character_id,
    evt.victim_character_id,
    evt.loss_type || "",
    evt.solar_system_id || "",
    evt.timestamp || ""
  );
}

function processJump(evt: JumpEventData, timestamp: string): void {
  const db = getDb();
  db.prepare(
    `INSERT INTO jumps (source_gate_id, dest_gate_id, character_id, timestamp)
     VALUES (?, ?, ?, ?)`
  ).run(
    evt.source_gate_id,
    evt.dest_gate_id,
    evt.character_id,
    evt.timestamp || timestamp
  );
}

// ---- Routing a single Sui event to the right processor ----

function handleEvent(event: SuiEvent): void {
  const eventType = event.type;
  const parsed = event.parsedJson as Record<string, string>;
  const timestamp = event.timestampMs
    ? new Date(Number(event.timestampMs)).toISOString()
    : new Date().toISOString();

  if (eventType.includes("::proposal::ProposalCreated")) {
    processProposalCreated(parsed as unknown as ProposalCreatedEvent, timestamp);
  } else if (eventType.includes("::proposal::ProposalSigned")) {
    processProposalSigned(parsed as unknown as ProposalSignedEvent, timestamp);
  } else if (eventType.includes("::proposal::AgentAutoSigned")) {
    processAgentAutoSigned(parsed as unknown as AgentAutoSignedEvent, timestamp);
  } else if (eventType.includes("::proposal::ProposalExecuted")) {
    processProposalExecuted(parsed as unknown as ProposalExecutedEvent, timestamp);
  } else if (eventType.includes("::proposal::ProposalMarkedExpired")) {
    processProposalMarkedExpired(parsed as unknown as ProposalMarkedExpiredEvent);
  } else if (eventType.includes("::treasury::PaidOut")) {
    processPaidOut(parsed as unknown as PaidOutEvent, timestamp);
  } else if (eventType.includes("KillmailCreatedEvent") || eventType.includes("KillMailCreatedEvent")) {
    processKillmail(parsed as unknown as KillmailCreatedEvent);
  } else if (eventType.includes("JumpEvent")) {
    processJump(parsed as unknown as JumpEventData, timestamp);
  }
}

// ---- Generic paginated event fetcher ----

async function fetchAndProcess(
  cursorKey: string,
  queryFilter: SuiEventFilter,
): Promise<void> {
  const sui = getClient();
  let cursor = loadCursor(cursorKey);
  let hasMore = true;

  while (hasMore) {
    const page = await sui.queryEvents({
      query: queryFilter,
      cursor: cursor ?? undefined,
      limit: PAGE_LIMIT,
      order: "ascending",
    });

    for (const evt of page.data) {
      handleEvent(evt);
    }

    if (page.data.length > 0) {
      const last = page.data[page.data.length - 1];
      cursor = { txDigest: last.id.txDigest, eventSeq: last.id.eventSeq };
      saveCursor(cursorKey, cursor);
    }

    hasMore = page.hasNextPage;
  }
}

// ---- Poll loops ----

async function pollTreasuryEvents(): Promise<void> {
  if (!config.packageId) {
    // No package deployed yet, skip silently
    return;
  }

  const modules = ["treasury", "proposal", "roles", "gate_sync"];
  for (const mod of modules) {
    try {
      await fetchAndProcess(`pkg:${mod}`, {
        MoveModule: { package: config.packageId, module: mod },
      });
    } catch (err) {
      console.error(`[indexer] Error polling ${mod}:`, err);
    }
  }
}

async function pollEveWorldEvents(): Promise<void> {
  if (!config.worldPackageId) return;

  // KillMail events
  try {
    await fetchAndProcess("eve:killmail", {
      MoveModule: { package: config.worldPackageId, module: "kill_mail" },
    });
  } catch (err) {
    console.error("[indexer] Error polling killmail events:", err);
  }

  // Jump events
  try {
    await fetchAndProcess("eve:jump", {
      MoveModule: { package: config.worldPackageId, module: "gate" },
    });
  } catch (err) {
    console.error("[indexer] Error polling jump events:", err);
  }
}

export function startIndexer(): void {
  console.log("[indexer] Starting event indexer...");
  if (config.packageId) {
    console.log(`[indexer] Treasury package: ${config.packageId}`);
  } else {
    console.log("[indexer] No PACKAGE_ID set -- treasury indexing disabled.");
  }
  console.log(`[indexer] World package: ${config.worldPackageId}`);

  // Initial run
  pollTreasuryEvents();
  pollEveWorldEvents();

  // Recurring polls
  setInterval(pollTreasuryEvents, TREASURY_POLL_MS);
  setInterval(pollEveWorldEvents, EVE_POLL_MS);
}
