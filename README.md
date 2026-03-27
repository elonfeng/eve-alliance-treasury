# EVE Frontier — Alliance Multi-Sig Treasury

**EVE Frontier x Sui Hackathon 2026**

On-chain governance and treasury management for EVE Frontier alliances. No single person can move funds — every payout requires multi-sig approval. Governance decisions can atomically update Smart Gate access in the same transaction.

---

## The Problem

In EVE, alliance leaders routinely disappear with the entire war chest. There is no trustless way to enforce spending rules, require multi-party approval, or produce a tamper-proof audit trail. CCP's current on-chain primitives give one director unilateral withdrawal access.

---

## What This Builds

**Four Move modules on Sui:**

| Module | Purpose |
|--------|---------|
| `treasury` | Alliance vault — holds SUI, only releases via approved proposals |
| `roles` | Member registry with role-based permissions (Commander / Treasurer / Elder / Auditor) |
| `proposal` | Multi-sig proposal flow with tiered signature thresholds |
| `gate_sync` | Smart Gate extension — whitelisted members get JumpPermits |

---

## Tiered Approval Thresholds

| Amount | Required Signatures |
|--------|-------------------|
| < 100 SUI | 2 signatures |
| 100 – 1,000 SUI | 3 signatures |
| > 1,000 SUI | 4 signatures |

---

## Architecture

```
create_treasury()  →  AllianceTreasury (shared) + AdminCap (owned by deployer)
create_registry()  →  RoleRegistry (shared)
add_member()       →  register wallets with role bitmask

create_proposal()  →  BudgetProposal (shared), proposer auto-signs
sign_proposal()    →  each member adds their signature
execute_proposal() →  threshold met → treasury::payout() transfers SUI
                       ProposalExecuted event = immutable audit record

[PTB: atomic governance + gate update]
  Step 1: execute_proposal(proposal, treasury, registry, clock)  → payout
  Step 2: whitelist_member(whitelist, admin_cap, new_member)     → gate access
  Both succeed or both fail.
```

---

## Key Sui Features Used

- **PTB (Programmable Transaction Blocks)** — financial payout + gate whitelist update in one atomic transaction
- **`public(package)` visibility** — `treasury::payout` is only callable from within the package; no external contract can drain the vault
- **Shared + Owned object model** — treasury and proposals are shared (anyone can interact); AdminCap is owned (only holder can administrate)
- **Dynamic Tables** — proposal signatures stored efficiently per proposal
- **On-chain events** — `ProposalExecuted` provides a permanent, queryable audit trail
- **Smart Gate Extension (Typed Witness)** — `AllianceAuth` witness restricts gate access to whitelisted members
- **Move enums** — `ProposalStatus` as a first-class enum type

---

## Build & Test

```bash
# Build
sui move build

# Run tests (20 tests covering all modules)
sui move test
```

---

## Deploy to Testnet

```bash
# Switch to testnet
sui client switch --env testnet

# Get testnet SUI (if needed)
sui client faucet

# Publish
sui client publish --gas-budget 200000000

# Note the PACKAGE_ID from the output
```

---

## Demo — CLI

```bash
cd scripts
cp .env.example .env
# Edit .env, set PACKAGE_ID from publish output
npm install
npx tsx demo.ts
```

The demo script runs the full governance flow:
1. Creates treasury + registry
2. Adds members with roles
3. Deposits SUI
4. Creates a budget proposal (proposer auto-signs)
5. Shows multi-sig threshold check
6. Creates gate whitelist for access control

---

## Demo — Web dApp

```bash
cd dapp
npm install  # or pnpm install
# Edit .env, set VITE_PACKAGE_ID
npm run dev
```

The dApp provides a visual interface for all treasury operations:
- Create treasury and manage roles
- Submit and sign proposals
- Execute payouts
- Emergency freeze

---

## Project Structure

```
eve-alliance-treasury/
├── Move.toml                 # Package config
├── sources/
│   ├── treasury.move         # Core vault module
│   ├── roles.move            # Role registry + tiered thresholds
│   ├── proposal.move         # Multi-sig proposal flow
│   └── gate_sync.move        # Smart Gate extension
├── tests/
│   └── treasury_tests.move   # 20 unit tests
├── scripts/
│   ├── demo.ts               # CLI demo script
│   └── .env.example          # Config template
└── dapp/
    └── src/App.tsx            # React frontend
```

---

## Hackathon Categories

- **Technical Implementation** — PTB atomic execution, `public(package)` access control, tiered multi-sig, composable gate integration, Move enums
- **Utility** — Solves real EVE alliance fund management problem (scams, rug pulls, no audit trail)
- **Creative** — Governance decisions atomically update in-game infrastructure

---

## Repository

https://github.com/elonfeng/eve-alliance-treasury
