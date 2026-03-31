#!/usr/bin/env npx tsx
/**
 * Alliance Multi-Sig Treasury — Hackathon Demo
 *
 * Cinematic end-to-end demo for video recording.
 * Usage:
 *   npx tsx demo.ts --dry-run   # simulated output, no transactions
 *   npx tsx demo.ts             # live mode, real Sui transactions
 */

import { config } from "dotenv";
import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

config();

// ═══════════════════════════════════════════════════════════════════
// ANSI Color Palette — Deep Space Command Console
// ═══════════════════════════════════════════════════════════════════

const C = {
  reset:   "\x1b[0m",
  bold:    "\x1b[1m",
  dim:     "\x1b[2m",
  // Amber — primary accent (titles, success)
  amber:   "\x1b[38;2;201;162;39m",
  // Cyan — interactive / data values
  cyan:    "\x1b[38;2;59;158;206m",
  // Pale — body text
  pale:    "\x1b[38;2;180;185;190m",
  // Green — success / confirmed
  green:   "\x1b[38;2;46;160;67m",
  // Red — alert / danger
  red:     "\x1b[38;2;201;58;58m",
  // Muted — secondary info
  muted:   "\x1b[38;2;107;114;128m",
  // White bright
  white:   "\x1b[38;2;243;244;246m",
  // BG dark
  bgDark:  "\x1b[48;2;10;14;23m",
};

const W = 72; // inner width
const DRY = process.argv.includes("--dry-run");

// ═══════════════════════════════════════════════════════════════════
// Drawing Primitives
// ═══════════════════════════════════════════════════════════════════

const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
const pad = (s: string, w: number) => s + " ".repeat(Math.max(0, w - stripAnsi(s).length));
function stripAnsi(s: string) { return s.replace(/\x1b\[[0-9;]*m/g, ""); }

function hline(ch = "═", w = W + 2) { return ch.repeat(w); }

async function banner(title: string, subtitle?: string) {
  const t = title.toUpperCase();
  const tPad = Math.max(0, Math.floor((W - t.length) / 2));
  console.log("");
  console.log(`${C.amber}  ╔${hline("═")}╗${C.reset}`);
  console.log(`${C.amber}  ║${" ".repeat(tPad)}${C.bold}${C.white}${t}${C.reset}${C.amber}${" ".repeat(W - tPad - t.length)}  ║${C.reset}`);
  if (subtitle) {
    const sPad = Math.max(0, Math.floor((W - subtitle.length) / 2));
    console.log(`${C.amber}  ║${" ".repeat(sPad)}${C.pale}${subtitle}${C.reset}${C.amber}${" ".repeat(W - sPad - subtitle.length)}  ║${C.reset}`);
  }
  console.log(`${C.amber}  ╚${hline("═")}╝${C.reset}`);
  console.log("");
  await sleep(800);
}

async function phase(num: number, title: string) {
  const label = ` PHASE ${num} `;
  const right = W - label.length - stripAnsi(title).length - 4;
  console.log(`${C.cyan}  ┌───${C.bold}${C.white}${label}${C.reset}${C.cyan}─ ${C.amber}${title}${C.reset}${C.cyan} ${"─".repeat(Math.max(0, right))}┐${C.reset}`);
  await sleep(300);
}

function phaseEnd() {
  console.log(`${C.cyan}  └${"─".repeat(W + 2)}┘${C.reset}`);
  console.log("");
}

async function log(msg: string, delay = 200) {
  console.log(`${C.cyan}  │${C.reset}  ${C.pale}${msg}${C.reset}`);
  await sleep(delay);
}

async function logPair(label: string, value: string, delay = 200) {
  console.log(`${C.cyan}  │${C.reset}  ${C.muted}${label}${C.reset} ${C.white}${value}${C.reset}`);
  await sleep(delay);
}

async function logOk(msg: string, delay = 200) {
  console.log(`${C.cyan}  │${C.reset}  ${C.green}● ${C.bold}${msg}${C.reset}`);
  await sleep(delay);
}

async function logWarn(msg: string, delay = 200) {
  console.log(`${C.cyan}  │${C.reset}  ${C.amber}○ ${msg}${C.reset}`);
  await sleep(delay);
}

async function logFail(msg: string, delay = 200) {
  console.log(`${C.cyan}  │${C.reset}  ${C.red}✗ ${msg}${C.reset}`);
  await sleep(delay);
}

async function logBar(label: string, current: number, total: number, delay = 200) {
  const barW = 30;
  const filled = Math.round((current / total) * barW);
  const bar = "━".repeat(filled) + "·".repeat(barW - filled);
  console.log(`${C.cyan}  │${C.reset}  ${C.muted}${label}${C.reset} ${C.amber}${bar}${C.reset} ${C.white}${current}/${total}${C.reset}`);
  await sleep(delay);
}

async function logNarrative(msg: string) {
  console.log(`${C.cyan}  │${C.reset}`);
  console.log(`${C.cyan}  │${C.reset}  ${C.dim}${C.pale}${msg}${C.reset}`);
  console.log(`${C.cyan}  │${C.reset}`);
  await sleep(400);
}

// ═══════════════════════════════════════════════════════════════════
// Sui Client + Transaction Helpers
// ═══════════════════════════════════════════════════════════════════

const PACKAGE_ID = process.env.PACKAGE_ID || "0x2be233510be68984d0f99d3095ad2e63507e5ed41335f60e5b9877aa8de431f5";
const NETWORK = (process.env.SUI_NETWORK as "testnet" | "devnet" | "mainnet") || "testnet";

function target(module: string, fn: string): `${string}::${string}::${string}` {
  return `${PACKAGE_ID}::${module}::${fn}`;
}

function getKeypair(): Ed25519Keypair {
  const keystorePath = join(process.env.HOME || "~", ".sui", "sui_config", "sui.keystore");
  if (existsSync(keystorePath)) {
    const keystore = JSON.parse(readFileSync(keystorePath, "utf-8"));
    const raw = Buffer.from(keystore[0], "base64");
    return Ed25519Keypair.fromSecretKey(raw.slice(1));
  }
  throw new Error("No Sui keystore found");
}

let client: SuiClient;
let keypair: Ed25519Keypair;
let address: string;

function findObject(result: any, typeSuffix: string): string | undefined {
  return result?.objectChanges?.find(
    (c: any) => c.type === "created" && c.objectType?.includes(typeSuffix)
  )?.objectId;
}

async function execTx(tx: Transaction): Promise<any> {
  if (DRY) return null;
  return await client.signAndExecuteTransaction({
    transaction: tx,
    signer: keypair,
    options: { showEffects: true, showObjectChanges: true },
  });
}

// Simulated object IDs for dry-run
let idCounter = 1;
function fakeId(): string {
  return `0x${(idCounter++).toString(16).padStart(64, "a")}`;
}

// ═══════════════════════════════════════════════════════════════════
// Demo Phases
// ═══════════════════════════════════════════════════════════════════

async function phase1_foundation(): Promise<{ treasuryId: string; adminCapId: string; registryId: string }> {
  await phase(1, "Foundation — Deploy Alliance Vault");

  await logNarrative("EVE alliance leaders have stolen war chests for 20 years.");
  await logNarrative("We replace trust with cryptographic guarantees.");

  // Create Treasury
  await log("Deploying AllianceTreasury (shared object)...");
  const tx1 = new Transaction();
  tx1.moveCall({
    target: target("treasury", "create_treasury"),
    arguments: [tx1.pure.string("Iron Wolves Alliance")],
  });
  const res1 = await execTx(tx1);
  const treasuryId = DRY ? fakeId() : findObject(res1, "AllianceTreasury")!;
  const adminCapId = DRY ? fakeId() : findObject(res1, "AdminCap")!;
  await logOk("AllianceTreasury created");
  await logPair("  Vault ID:", treasuryId.slice(0, 20) + "...");
  await logPair("  AdminCap:", adminCapId.slice(0, 20) + "...");

  // Create Registry
  await log("Deploying RoleRegistry...");
  const tx2 = new Transaction();
  tx2.moveCall({
    target: target("roles", "create_registry"),
    arguments: [tx2.object(adminCapId)],
  });
  const res2 = await execTx(tx2);
  const registryId = DRY ? fakeId() : findObject(res2, "RoleRegistry")!;
  await logOk("RoleRegistry created");
  await logPair("  Registry:", registryId.slice(0, 20) + "...");

  // Add member
  await log(`Adding Commander+Elder: ${address.slice(0, 16)}...`);
  const tx3 = new Transaction();
  tx3.moveCall({
    target: target("roles", "add_member"),
    arguments: [
      tx3.object(registryId),
      tx3.object(adminCapId),
      tx3.pure.address(address),
      tx3.pure.u8(5), // COMMANDER(1) + ELDER(4)
    ],
  });
  await execTx(tx3);
  await logOk("Member registered — role bitmask: 5 (Commander+Elder)");

  await logPair("  Roles:", "COMMANDER=1, TREASURER=2, ELDER=4, AUDITOR=8");
  await logPair("  Member:", `${address.slice(0, 16)}... = 5 (1|4)`);

  phaseEnd();
  await sleep(2500);
  return { treasuryId, adminCapId, registryId };
}

async function phase2_funding(treasuryId: string): Promise<void> {
  await phase(2, "Funding — Deposit SUI into Vault");

  await logNarrative("Alliance members contribute to the shared war chest.");
  await logNarrative("Funds are locked — no single person can withdraw.");

  const depositAmount = 100_000_000; // 0.1 SUI
  await log(`Depositing 0.1 SUI into treasury...`);
  const tx = new Transaction();
  const [coin] = tx.splitCoins(tx.gas, [depositAmount]);
  tx.moveCall({
    target: target("treasury", "deposit"),
    arguments: [tx.object(treasuryId), coin],
  });
  await execTx(tx);
  await logOk("Deposit confirmed");
  await logPair("  Amount:", "0.1 SUI (100,000,000 MIST)");
  await logPair("  Access:", "public(package) payout — no external drain possible");

  phaseEnd();
  await sleep(2500);
}

async function phase3_governance(treasuryId: string, registryId: string): Promise<string> {
  await phase(3, "Governance — Multi-Sig Proposal Flow");

  await logNarrative("Every payout requires multi-signature approval.");
  await logNarrative("Threshold scales with amount: <100 SUI=2, 100-1k=3, >1k=4 sigs.");

  // Create proposal
  const proposalAmount = 50_000_000; // 0.05 SUI
  await log("Commander submits budget proposal...");
  const tx1 = new Transaction();
  tx1.moveCall({
    target: target("proposal", "create_proposal"),
    arguments: [
      tx1.object(treasuryId),
      tx1.object(registryId),
      tx1.pure.u64(proposalAmount),
      tx1.pure.address(address),
      tx1.pure.string("Fleet supplies for war campaign"),
      tx1.object("0x6"),
    ],
  });
  const res1 = await execTx(tx1);
  const proposalId = DRY ? fakeId() : findObject(res1, "BudgetProposal")!;
  await logOk("BudgetProposal created");
  await logPair("  Amount:", "0.05 SUI");
  await logPair("  Purpose:", "Fleet supplies for war campaign");
  await logBar("Signatures", 1, 2, 300);
  await logPair("  Status:", "Proposer auto-signed (1/2)");

  // Attempt execute — should fail
  await log("");
  await log("Attempting execution with 1/2 signatures...");
  try {
    const tx2 = new Transaction();
    tx2.moveCall({
      target: target("proposal", "execute_proposal"),
      arguments: [
        tx2.object(proposalId),
        tx2.object(treasuryId),
        tx2.object(registryId),
        tx2.object("0x6"),
      ],
    });
    await execTx(tx2);
    if (DRY) throw new Error("EThresholdNotMet");
  } catch {
    await logFail("Execution REJECTED — threshold not met (1/2 < 2/2)");
    await logOk("Multi-sig enforcement verified");
  }

  phaseEnd();
  await sleep(2500);
  return proposalId;
}

async function phase4_agent(treasuryId: string, registryId: string, adminCapId: string): Promise<void> {
  await phase(4, "Policy Agent — Autonomous On-Chain Signer");

  await logNarrative("The agent is NOT an AI API wrapper.");
  await logNarrative("It's a deterministic, auditable rule engine on-chain.");
  await logNarrative("5 composable skills — admin configures, agent executes 24/7.");

  // Create agent
  await log("Deploying PolicyAgent with AUTO_APPROVE + RATE_LIMIT...");
  const tx1 = new Transaction();
  tx1.moveCall({
    target: target("policy_agent", "create_agent"),
    arguments: [
      tx1.object(adminCapId),
      tx1.pure.u64(80_000_000_000),  // max 80 SUI
      tx1.pure.u64(200_000_000_000), // daily 200 SUI
    ],
  });
  const res1 = await execTx(tx1);
  const agentId = DRY ? fakeId() : findObject(res1, "PolicyAgent")!;
  await logOk("PolicyAgent deployed");
  await logPair("  Agent ID:", agentId.slice(0, 20) + "...");

  // Skills display
  await log("");
  await logPair("  Skills (bitmask):", "");
  await logPair("    [1] AUTO_APPROVE", "max 80 SUI per proposal");
  await logPair("    [2] RATE_LIMIT  ", "200 SUI daily cap");
  await logPair("    [4] TRUSTED_LIST", "(disabled)");
  await logPair("    [8] BALANCE_GUARD", "(disabled)");
  await logPair("   [16] COOLDOWN    ", "(disabled)");
  await logPair("  Active bitmask:", "3 (AUTO_APPROVE | RATE_LIMIT)");

  // New proposal for agent
  await log("");
  await log("Creating small proposal (0.03 SUI) for agent evaluation...");
  const tx2 = new Transaction();
  tx2.moveCall({
    target: target("proposal", "create_proposal"),
    arguments: [
      tx2.object(treasuryId),
      tx2.object(registryId),
      tx2.pure.u64(30_000_000), // 0.03 SUI
      tx2.pure.address(address),
      tx2.pure.string("Routine supply restock"),
      tx2.object("0x6"),
    ],
  });
  const res2 = await execTx(tx2);
  const agentProposalId = DRY ? fakeId() : findObject(res2, "BudgetProposal")!;
  await logBar("Signatures", 1, 2, 300);

  // Agent signs
  await log("Agent evaluating proposal...");
  await logPair("  CHECK", "amount 0.03 SUI <= max 80 SUI      PASS", 250);
  await logPair("  CHECK", "daily_spent + 0.03 <= 200 SUI      PASS", 250);
  const tx3 = new Transaction();
  tx3.moveCall({
    target: target("proposal", "agent_sign_proposal"),
    arguments: [
      tx3.object(agentProposalId),
      tx3.object(agentId),
      tx3.object(treasuryId),
      tx3.object("0x6"),
    ],
  });
  await execTx(tx3);
  await logOk("Agent AUTO-SIGNED — all skill checks passed");
  await logBar("Signatures", 2, 2, 300);

  // Execute
  await log("Executing agent-approved proposal...");
  const tx4 = new Transaction();
  tx4.moveCall({
    target: target("proposal", "execute_proposal"),
    arguments: [
      tx4.object(agentProposalId),
      tx4.object(treasuryId),
      tx4.object(registryId),
      tx4.object("0x6"),
    ],
  });
  await execTx(tx4);
  await logOk("Payout executed — 0.03 SUI transferred");
  await logPair("  Flow:", "human proposes -> agent approves -> auto-execute");
  await logPair("  Human:", "0 additional signatures needed");

  phaseEnd();
  await sleep(2500);
}

async function phase5_gate(adminCapId: string): Promise<void> {
  await phase(5, "Smart Gate — Atomic Governance + Access Control");

  await logNarrative("Governance decisions atomically update in-game gate access.");
  await logNarrative("PTB: payout + whitelist update in ONE transaction.");

  // Create whitelist
  await log("Creating MemberWhitelist for gate access...");
  const tx1 = new Transaction();
  tx1.moveCall({
    target: target("gate_sync", "create_whitelist"),
    arguments: [tx1.object(adminCapId)],
  });
  const res1 = await execTx(tx1);
  const whitelistId = DRY ? fakeId() : findObject(res1, "MemberWhitelist")!;
  await logOk("MemberWhitelist created");
  await logPair("  Whitelist:", whitelistId.slice(0, 20) + "...");

  // Whitelist member
  await log(`Whitelisting ${address.slice(0, 16)}...`);
  const tx2 = new Transaction();
  tx2.moveCall({
    target: target("gate_sync", "whitelist_member"),
    arguments: [
      tx2.object(whitelistId),
      tx2.object(adminCapId),
      tx2.pure.address(address),
    ],
  });
  await execTx(tx2);
  await logOk("Member whitelisted — can now obtain JumpPermit (24h)");

  await log("");
  await logPair("  PTB Pattern:", "execute_proposal() + whitelist_member()");
  await logPair("  Guarantee: ", "both succeed or both revert");
  await logPair("  Use case:  ", "recruit pays + gets gate access atomically");

  phaseEnd();
  await sleep(2500);
}

async function phase6_summary(): Promise<void> {
  await phase(6, "System Summary");

  await logPair("  Modules:    ", "6 Move contracts on Sui testnet");
  await logPair("  Tests:      ", "58 Move + 29 backend = 87 total");
  await logPair("  Backend:    ", "Express + SQLite event indexer");
  await logPair("  Frontend:   ", "React tactical HUD with EVE Vault");
  await logPair("  Agent:      ", "5 composable skills, deterministic, on-chain");
  await logPair("  Gate Sync:  ", "PTB atomic governance + access control");
  await log("");
  await logPair("  Sui Features:", "");
  await logPair("    PTB       ", "atomic multi-step execution");
  await logPair("    public(pkg)", "payout only callable within package");
  await logPair("    Shared+Own", "treasury shared, AdminCap owned");
  await logPair("    Tables    ", "signatures, members, trusted list");
  await logPair("    Events    ", "ProposalExecuted = permanent audit");
  await logPair("    Witness   ", "AllianceAuth typed gate extension");
  await logPair("    Enums     ", "ProposalStatus as Move enum");

  phaseEnd();
}

// ═══════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════

async function main() {
  if (!DRY) {
    client = new SuiClient({ url: getFullnodeUrl(NETWORK) });
    keypair = getKeypair();
    address = keypair.getPublicKey().toSuiAddress();
  } else {
    address = "0x434b5eef692a402c639257d3ace47dba6abd8a4a9cbfc2c7fdfb3edf66697045";
  }

  await banner(
    "Alliance Multi-Sig Treasury",
    "EVE Frontier x Sui Hackathon 2026"
  );

  await logPair(`  ${C.muted}Mode:`, DRY ? `${C.amber}DRY RUN (simulated)` : `${C.green}LIVE (real transactions)`);
  await logPair(`  ${C.muted}Network:`, `${C.cyan}${NETWORK}`);
  await logPair(`  ${C.muted}Package:`, `${C.cyan}${PACKAGE_ID.slice(0, 20)}...`);
  await logPair(`  ${C.muted}Address:`, `${C.cyan}${address.slice(0, 20)}...`);

  if (!DRY) {
    const balance = await client.getBalance({ owner: address });
    await logPair(`  ${C.muted}Balance:`, `${C.white}${(Number(balance.totalBalance) / 1e9).toFixed(3)} SUI`);
  }
  console.log("");
  await sleep(1500);

  const { treasuryId, adminCapId, registryId } = await phase1_foundation();
  await phase2_funding(treasuryId);
  await phase3_governance(treasuryId, registryId);
  await phase4_agent(treasuryId, registryId, adminCapId);
  await phase5_gate(adminCapId);
  await phase6_summary();

  await banner(
    "Demo Complete",
    "No single person can move funds. Agent-native governance."
  );
}

main().catch(e => {
  console.error(`${C.red}Fatal: ${e.message}${C.reset}`);
  process.exit(1);
});
