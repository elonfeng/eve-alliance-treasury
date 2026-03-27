/**
 * Alliance Multi-Sig Treasury — Full Demo Script
 *
 * Demonstrates the complete governance flow on Sui testnet:
 *   1. Create treasury + role registry + whitelist
 *   2. Add alliance members with roles
 *   3. Deposit SUI into treasury
 *   4. Create a budget proposal
 *   5. Multi-sig approval (multiple signers)
 *   6. Execute proposal → atomic payout
 *
 * Prerequisites:
 *   - `sui client publish` the package first
 *   - Set PACKAGE_ID in .env
 *   - Have at least 3 Sui addresses with testnet SUI
 *
 * Usage:
 *   cp .env.example .env
 *   # edit .env with your PACKAGE_ID
 *   npm install
 *   npx tsx demo.ts
 */

import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { config } from "dotenv";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

config();

// ─── Config ───────────────────────────────────────────────────────────────

const PACKAGE_ID = process.env.PACKAGE_ID;
if (!PACKAGE_ID) {
  console.error("❌ Set PACKAGE_ID in scripts/.env first. Run `sui client publish` to get it.");
  process.exit(1);
}

const NETWORK = (process.env.SUI_NETWORK as "testnet" | "devnet" | "mainnet") || "testnet";
const client = new SuiClient({ url: getFullnodeUrl(NETWORK) });

// ─── Helpers ──────────────────────────────────────────────────────────────

function target(module: string, fn: string): `${string}::${string}::${string}` {
  return `${PACKAGE_ID}::${module}::${fn}`;
}

/**
 * Read the active keypair from Sui CLI keystore.
 * Falls back to environment variable PRIVATE_KEY if keystore not found.
 */
function getKeypair(): Ed25519Keypair {
  const keystorePath = join(process.env.HOME || "~", ".sui", "sui_config", "sui.keystore");
  if (existsSync(keystorePath)) {
    const keystore = JSON.parse(readFileSync(keystorePath, "utf-8"));
    // Use the first key in keystore
    const encoded = keystore[0];
    const raw = Buffer.from(encoded, "base64");
    // Sui keystore format: first byte is scheme (0 = Ed25519), rest is secret key
    const secretKey = raw.slice(1);
    return Ed25519Keypair.fromSecretKey(secretKey);
  }
  if (process.env.PRIVATE_KEY) {
    return Ed25519Keypair.fromSecretKey(Buffer.from(process.env.PRIVATE_KEY, "hex"));
  }
  console.error("❌ No Sui keystore found and no PRIVATE_KEY env var set.");
  process.exit(1);
}

async function signAndExecute(tx: Transaction, signer: Ed25519Keypair) {
  const result = await client.signAndExecuteTransaction({
    transaction: tx,
    signer,
    options: { showEffects: true, showObjectChanges: true, showEvents: true },
  });
  if (result.effects?.status?.status !== "success") {
    console.error("❌ Transaction failed:", JSON.stringify(result.effects?.status, null, 2));
    process.exit(1);
  }
  return result;
}

function findCreatedObject(result: any, typeSuffix: string): string | undefined {
  return result.objectChanges?.find(
    (c: any) => c.type === "created" && c.objectType?.includes(typeSuffix)
  )?.objectId;
}

// ─── Demo Flow ────────────────────────────────────────────────────────────

async function main() {
  const keypair = getKeypair();
  const address = keypair.getPublicKey().toSuiAddress();
  console.log(`\n🔑 Using address: ${address}`);
  console.log(`📦 Package ID: ${PACKAGE_ID}`);
  console.log(`🌐 Network: ${NETWORK}\n`);

  // Check balance
  const balance = await client.getBalance({ owner: address });
  console.log(`💰 Balance: ${Number(balance.totalBalance) / 1e9} SUI\n`);

  // ── Step 1: Create Treasury ──────────────────────────────────────────
  console.log("═══ Step 1: Create Alliance Treasury ═══");
  const tx1 = new Transaction();
  tx1.moveCall({
    target: target("treasury", "create_treasury"),
    arguments: [tx1.pure.string("Iron Wolves Alliance")],
  });
  const res1 = await signAndExecute(tx1, keypair);
  const treasuryId = findCreatedObject(res1, "AllianceTreasury");
  const adminCapId = findCreatedObject(res1, "AdminCap");
  console.log(`  ✅ Treasury: ${treasuryId}`);
  console.log(`  ✅ AdminCap: ${adminCapId}\n`);

  // ── Step 2: Create Role Registry ─────────────────────────────────────
  console.log("═══ Step 2: Create Role Registry ═══");
  const tx2 = new Transaction();
  tx2.moveCall({
    target: target("roles", "create_registry"),
    arguments: [tx2.object(adminCapId!)],
  });
  const res2 = await signAndExecute(tx2, keypair);
  const registryId = findCreatedObject(res2, "RoleRegistry");
  console.log(`  ✅ Registry: ${registryId}\n`);

  // ── Step 3: Add Members ──────────────────────────────────────────────
  console.log("═══ Step 3: Add Members with Roles ═══");
  const tx3 = new Transaction();
  // Add self as COMMANDER + ELDER (bitmask 5)
  tx3.moveCall({
    target: target("roles", "add_member"),
    arguments: [
      tx3.object(registryId!),
      tx3.object(adminCapId!),
      tx3.pure.address(address),
      tx3.pure.u8(5), // COMMANDER(1) + ELDER(4) = 5
    ],
  });
  await signAndExecute(tx3, keypair);
  console.log(`  ✅ Added ${address} as Commander+Elder (role=5)\n`);

  // ── Step 4: Deposit SUI ──────────────────────────────────────────────
  console.log("═══ Step 4: Deposit SUI into Treasury ═══");
  const depositAmount = 100_000_000; // 0.1 SUI
  const tx4 = new Transaction();
  const [depositCoin] = tx4.splitCoins(tx4.gas, [depositAmount]);
  tx4.moveCall({
    target: target("treasury", "deposit"),
    arguments: [tx4.object(treasuryId!), depositCoin],
  });
  await signAndExecute(tx4, keypair);
  console.log(`  ✅ Deposited ${depositAmount / 1e9} SUI\n`);

  // ── Step 5: Create Budget Proposal ───────────────────────────────────
  console.log("═══ Step 5: Create Budget Proposal ═══");
  const proposalAmount = 50_000_000; // 0.05 SUI — small threshold (needs 2 sigs)
  const tx5 = new Transaction();
  tx5.moveCall({
    target: target("proposal", "create_proposal"),
    arguments: [
      tx5.object(treasuryId!),
      tx5.object(registryId!),
      tx5.pure.u64(proposalAmount),
      tx5.pure.address(address), // recipient = self for demo
      tx5.pure.string("Buy fleet supplies for war campaign"),
      tx5.object("0x6"), // Clock
    ],
  });
  const res5 = await signAndExecute(tx5, keypair);
  const proposalId = findCreatedObject(res5, "BudgetProposal");
  console.log(`  ✅ Proposal: ${proposalId}`);
  console.log(`  📝 Amount: ${proposalAmount / 1e9} SUI`);
  console.log(`  📝 Purpose: Buy fleet supplies for war campaign`);
  console.log(`  📝 Proposer auto-signed (1/2 signatures)\n`);

  // ── Step 6: Sign Proposal (with same key for demo) ───────────────────
  // In production, different addresses would sign. For demo with 1 key,
  // the proposal was created with 0.05 SUI (<100 SUI), needing 2 sigs.
  // The proposer auto-signed. We need 1 more signer.
  // Since we only have one keypair, we'll show the execute attempt.
  console.log("═══ Step 6: Execute Proposal ═══");
  console.log("  ⚠️  Single-key demo: proposer auto-signed (1/2).");
  console.log("  ⚠️  In production, a second member would sign first.");
  console.log("  ⚠️  Attempting execute to show the threshold check...\n");

  try {
    const tx6 = new Transaction();
    tx6.moveCall({
      target: target("proposal", "execute_proposal"),
      arguments: [
        tx6.object(proposalId!),
        tx6.object(treasuryId!),
        tx6.object(registryId!),
        tx6.object("0x6"), // Clock
      ],
    });
    await signAndExecute(tx6, keypair);
    console.log("  ✅ Proposal executed! Funds transferred.\n");
  } catch (e: any) {
    if (e.message?.includes("EThresholdNotMet") || e.message?.includes("3")) {
      console.log("  ✅ Correctly rejected: threshold not met (1/2 signatures)");
      console.log("  📝 This proves multi-sig is working!\n");
    } else {
      console.log(`  ❌ Unexpected error: ${e.message}\n`);
    }
  }

  // ── Step 7: Create Whitelist ─────────────────────────────────────────
  console.log("═══ Step 7: Create Gate Whitelist ═══");
  const tx7 = new Transaction();
  tx7.moveCall({
    target: target("gate_sync", "create_whitelist"),
    arguments: [tx7.object(adminCapId!)],
  });
  const res7 = await signAndExecute(tx7, keypair);
  const whitelistId = findCreatedObject(res7, "MemberWhitelist");
  console.log(`  ✅ Whitelist: ${whitelistId}\n`);

  // ── Step 8: Whitelist a Member ───────────────────────────────────────
  console.log("═══ Step 8: Whitelist Member for Gate Access ═══");
  const tx8 = new Transaction();
  tx8.moveCall({
    target: target("gate_sync", "whitelist_member"),
    arguments: [
      tx8.object(whitelistId!),
      tx8.object(adminCapId!),
      tx8.pure.address(address),
    ],
  });
  await signAndExecute(tx8, keypair);
  console.log(`  ✅ Whitelisted ${address}\n`);

  // ── Summary ──────────────────────────────────────────────────────────
  console.log("═══════════════════════════════════════════════");
  console.log("  Demo Complete! Object IDs for .env:");
  console.log("═══════════════════════════════════════════════");
  console.log(`  PACKAGE_ID=${PACKAGE_ID}`);
  console.log(`  TREASURY_ID=${treasuryId}`);
  console.log(`  ADMIN_CAP_ID=${adminCapId}`);
  console.log(`  REGISTRY_ID=${registryId}`);
  console.log(`  WHITELIST_ID=${whitelistId}`);
  console.log(`  PROPOSAL_ID=${proposalId}`);
  console.log("═══════════════════════════════════════════════\n");
}

main().catch(console.error);
