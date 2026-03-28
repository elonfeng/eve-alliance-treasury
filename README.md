# EVE Frontier -- Alliance Multi-Sig Treasury

**EVE Frontier x Sui Hackathon 2026**

On-chain multi-sig governance, policy-agent-driven automation, and Smart Gate access control for EVE Frontier alliances. No single person can move funds. Every payout requires multi-sig approval, every action is auditable, and governance decisions atomically update in-game infrastructure.

---

## The Problem

In EVE, alliance leaders routinely disappear with the entire war chest. There is no trustless mechanism to enforce spending rules, require multi-party approval, or produce a tamper-proof audit trail. The existing on-chain primitives give a single director unilateral withdrawal access. Billions in ISK and real value have been lost to rug pulls, insider fraud, and opaque governance.

**What alliances need:**

- Funds locked behind multi-signature approval thresholds
- Tiered governance that scales with transaction size
- Autonomous policy enforcement that does not depend on any single human
- Atomic linkage between financial decisions and in-game infrastructure (Smart Gates)
- A permanent, queryable audit trail for every SUI that moves

---

## Solution Overview

A full-stack system (contracts + indexer backend + web dApp) that replaces trust-based alliance treasuries with cryptographic guarantees:

- **Multi-sig proposals** with tiered signature thresholds (2/3/4 sigs based on amount)
- **Policy Agent** -- an on-chain autonomous signer with composable skill-based rules
- **Role-based access control** using bitmask permissions (Commander, Treasurer, Elder, Auditor)
- **Smart Gate integration** -- governance decisions atomically update jump access via PTB
- **Event-driven indexer** -- backend polls on-chain events (including EVE KillMail + JumpEvent) into SQLite for fast querying
- **58 unit tests** covering all modules including agent skill evaluation, threshold edge cases, and expiration flows

---

## Architecture

```
+------------------------------------------------------------------+
|                        FRONTEND (React dApp)                      |
|                                                                   |
|  Wallet Connect    Proposal Dashboard    Role Management    Audit |
|       |                   |                    |              |   |
+-------|-------------------|--------------------|--------------+---+
        |                   |                    |              |
        v                   v                    v              v
+------------------------------------------------------------------+
|                    BACKEND (Express + SQLite)                     |
|                                                                   |
|  /api/proposals   /api/audit   /api/killmails   /api/agent       |
|       |               |             |               |            |
|       +-------+-------+-------------+---------------+            |
|               |                                                  |
|         Event Indexer (polling)                                   |
|           |           |                                          |
|    Treasury Events   EVE World Events                            |
|    (Proposal, Payout, (KillMail,                                 |
|     AgentAutoSigned)  JumpEvent)                                 |
+----------|------------|------------------------------------------+
           |            |
           v            v
+------------------------------------------------------------------+
|                   ON-CHAIN (Sui Move Contracts)                   |
|                                                                   |
|  +----------+  +-------+  +----------+  +-----------+            |
|  | treasury |  | roles |  | proposal |  | gate_sync |            |
|  +----+-----+  +---+---+  +----+-----+  +-----+-----+           |
|       |             |           |              |                  |
|       +------+------+-----------+--------------+                  |
|              |                                                   |
|     +--------------+     +----------------------+                |
|     | policy_agent |     | integration_examples |                |
|     +--------------+     +----------------------+                |
|                                                                   |
|  PTB Atomic Execution:                                           |
|    Step 1: execute_proposal() --> payout SUI                     |
|    Step 2: whitelist_member() --> grant gate access               |
|    Both succeed or both revert.                                  |
+------------------------------------------------------------------+
```

---

## Move Modules

| Module | File | Purpose |
|--------|------|---------|
| `treasury` | `sources/treasury.move` | Alliance vault. Holds SUI, tracks deposits and payouts. Only releases funds via `public(package)` payout called from `proposal`. |
| `roles` | `sources/roles.move` | Member registry with bitmask role permissions. Computes tiered signature thresholds based on proposal amount. |
| `proposal` | `sources/proposal.move` | Multi-sig proposal lifecycle: create, sign, agent-sign, execute, expire. Emits `ProposalExecuted` as permanent audit record. |
| `gate_sync` | `sources/gate_sync.move` | Smart Gate extension using typed witness (`AllianceAuth`). Manages member whitelist and issues 24-hour JumpPermits. |
| `policy_agent` | `sources/policy_agent.move` | On-chain autonomous governance participant with 5 composable skills. Evaluates proposals deterministically and auto-signs when all checks pass. |
| `integration_examples` | `sources/integration_examples.move` | Read-only integration patterns showing how external protocols compose with treasury state (insurance, reputation, gate access). |

---

## Policy Agent: Agent-Native Governance

The Policy Agent is not a wrapper around an external AI API. It is an on-chain autonomous participant that embodies deterministic, auditable rules as composable "skills." Every evaluation is fully reproducible from chain state alone.

### Skill System (Bitmask, Composable)

| Bit | Skill | Value | Description |
|-----|-------|-------|-------------|
| 0 | `AUTO_APPROVE` | 1 | Auto-sign proposals below `max_auto_amount` |
| 1 | `RATE_LIMIT` | 2 | Enforce daily spending cap (`daily_limit`) |
| 2 | `TRUSTED_LIST` | 4 | Only auto-sign for pre-approved recipients |
| 3 | `BALANCE_GUARD` | 8 | Block if treasury balance would drop below reserve |
| 4 | `COOLDOWN` | 16 | Enforce minimum time between payouts to same recipient |

Skills are combined via bitwise OR. An agent with skills `= 11` (binary `01011`) has AUTO_APPROVE + RATE_LIMIT + BALANCE_GUARD active.

### Progressive Disclosure

The agent adapts governance complexity based on treasury needs:

| Treasury Stage | Recommended Skills | Bitmask |
|----------------|--------------------|---------|
| Small / new alliance | AUTO_APPROVE + RATE_LIMIT | 3 |
| Mid-size operations | + TRUSTED_LIST | 7 |
| Large war chest | + BALANCE_GUARD + COOLDOWN | 31 |

The admin can reconfigure skills at any time via `set_skills()` without redeploying.

### Design Philosophy

> "Agent value is not about being AI. It is about autonomous, trustworthy, tamper-proof governance execution."

- **Deterministic**: Same inputs always produce the same result. No RNG, no external oracle.
- **Auditable**: Every approval/rejection emits an `AgentEvaluated` event with a specific rejection reason code.
- **Composable**: Skills are independent checks composed via bitmask. Add or remove checks without affecting others.
- **Non-custodial**: The agent never holds funds. It only adds one signature toward the multi-sig threshold.

---

## Tiered Signature Thresholds

| Amount | Required Signatures | Rationale |
|--------|---------------------|-----------|
| < 100 SUI | 2 signatures | Routine operational expenses |
| 100 -- 1,000 SUI | 3 signatures | Mid-range spending requires broader consensus |
| > 1,000 SUI | 4 signatures | Large transfers require near-full council approval |

Thresholds are computed on-chain in `roles::required_signatures()`. The Policy Agent counts as one signature toward the threshold -- it reduces friction without eliminating human oversight.

---

## Sui Features Used

| Feature | Usage |
|---------|-------|
| **PTB (Programmable Transaction Blocks)** | Atomic execution: financial payout + gate whitelist update in one transaction. Both succeed or both revert. |
| **`public(package)` visibility** | `treasury::payout` is only callable from within the `alliance_treasury` package. No external contract can drain the vault. |
| **Shared + Owned object model** | Treasury, proposals, registry, and agent are shared (anyone can interact). AdminCap is owned (only holder can administrate). |
| **Dynamic Tables** | Proposal signatures, role mappings, trusted recipients, and cooldown trackers stored efficiently per object. |
| **On-chain events** | `ProposalExecuted`, `AgentEvaluated`, `PaidOut` provide a permanent, queryable audit trail. |
| **Smart Gate Extension (Typed Witness)** | `AllianceAuth` witness restricts gate access to whitelisted members. |
| **Move enums** | `ProposalStatus` as a first-class enum type (`Pending`, `Executed`, `Expired`). |
| **Bitmask composition** | Both roles (4-bit) and agent skills (5-bit) use bitmask patterns for gas-efficient, composable permissions. |

---

## EVE Frontier Integration

The backend indexer polls two categories of on-chain events:

### Treasury Events (10s polling interval)

| Event | Source Module | Indexed Data |
|-------|--------------|--------------|
| `ProposalCreated` | proposal | Proposal ID, amount, recipient, required sigs, expiry |
| `ProposalSigned` | proposal | Signer address, current sig count |
| `ProposalExecuted` | proposal | Executor, recipient, final amount |
| `AgentAutoSigned` | proposal | Agent ID, sig count after agent vote |
| `PaidOut` | treasury | Treasury ID, recipient, amount |

### EVE World Events (30s polling interval)

| Event | Source | Indexed Data |
|-------|--------|--------------|
| `KillMail` | EVE World contracts | Killer, victim, loss type, solar system |
| `JumpEvent` | EVE World contracts | Source gate, destination gate, character |

These events flow into SQLite and are served via REST endpoints (`/api/killmails`, `/api/audit`) for the frontend dashboard and external integrations.

---

## Deployed Addresses

| Item | Address |
|------|---------|
| Package ID | `0xbeffbe08c1a7b0ec9a108773707c8a2b6032cbf1b5d170188d646121f2ac24f3` |

> Note: The package will be redeployed with the `policy_agent` module included. The address above reflects the pre-agent deployment.

---

## Build and Test

```bash
# Build the Move contracts
sui move build

# Run all 58 tests
sui move test

# Run tests with verbose output
sui move test --verbose
```

### Test Coverage

The test suite (`tests/treasury_tests.move`) covers:

- Treasury creation, deposit, payout, and freeze/unfreeze flows
- Role registry CRUD and bitmask permission checks
- Proposal lifecycle: create, sign, execute, expire
- Tiered threshold enforcement (2-sig, 3-sig, 4-sig)
- Policy Agent skill evaluation (all 5 skills individually and combined)
- Agent auto-sign state updates (daily spent, cooldown tracking)
- Edge cases: duplicate signatures, expired proposals, frozen treasury, wrong treasury ID
- Integration example read-only queries

---

## Quick Start

### 1. Smart Contracts

```bash
# Clone the repository
git clone https://github.com/elonfeng/eve-alliance-treasury.git
cd eve-alliance-treasury

# Build
sui move build

# Run tests
sui move test

# Deploy to testnet
sui client switch --env testnet
sui client faucet
sui client publish --gas-budget 200000000
# Note the PACKAGE_ID from output
```

### 2. Backend (Event Indexer + REST API)

```bash
cd backend
npm install

# Configure environment
# Set PACKAGE_ID, SUI_RPC_URL in config

# Start the server (indexer + API on port 3001)
npm run dev
```

**API Endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Service health check |
| GET | `/api/proposals` | List all proposals with signatures |
| GET | `/api/audit` | Full payout audit trail |
| GET | `/api/killmails` | EVE KillMail events |
| GET | `/api/agent` | Policy Agent status and history |

### 3. Frontend (React dApp)

```bash
cd dapp
pnpm install

# Set VITE_PACKAGE_ID in .env
pnpm dev
```

The dApp provides a visual interface for:

- Creating treasuries and managing member roles
- Submitting, signing, and executing proposals
- Viewing Policy Agent evaluation status
- Emergency freeze controls
- Full audit trail with payout history

---

## Project Structure

```
eve-alliance-treasury/
├── Move.toml                          # Package config (depends on EVE World contracts)
├── sources/
│   ├── treasury.move                  # Core vault module
│   ├── roles.move                     # Role registry + tiered thresholds
│   ├── proposal.move                  # Multi-sig proposal flow + agent integration
│   ├── gate_sync.move                 # Smart Gate extension (typed witness)
│   ├── policy_agent.move              # On-chain autonomous governance agent
│   └── integration_examples.move      # Composability patterns for third parties
├── tests/
│   └── treasury_tests.move            # 58 unit tests
├── backend/
│   ├── src/
│   │   ├── index.ts                   # Express server + route registration
│   │   ├── indexer.ts                 # Event poller (treasury + EVE world events)
│   │   ├── db.ts                      # SQLite schema + connection
│   │   ├── config.ts                  # Environment configuration
│   │   ├── types.ts                   # TypeScript interfaces for events and DB rows
│   │   └── routes/
│   │       ├── health.ts              # Health check
│   │       ├── proposals.ts           # Proposal queries
│   │       ├── audit.ts               # Payout audit trail
│   │       ├── killmails.ts           # EVE KillMail queries
│   │       └── agent.ts               # Policy Agent status
│   └── package.json
├── dapp/
│   └── src/                           # React + Vite frontend
├── scripts/
│   └── demo.ts                        # CLI demo script (full governance flow)
└── README.md
```

---

## Hackathon Categories

### Technical Implementation

- PTB atomic execution linking financial payouts to Smart Gate access changes
- `public(package)` access control preventing external vault drainage
- Tiered multi-sig with amount-based threshold computation
- On-chain Policy Agent with 5 composable bitmask skills
- Move enums for type-safe proposal status
- Event-driven indexer architecture with cursor-based pagination

### Utility

- Solves a real, documented problem: EVE alliance fund mismanagement and rug pulls
- Replaces trust-based governance with cryptographic guarantees
- Policy Agent reduces operational overhead for routine payouts
- Full audit trail satisfies both alliance members and external auditors

### Creative

- Governance decisions atomically update in-game infrastructure (Smart Gate jump access)
- Agent-native design: deterministic, auditable, composable -- not an AI gimmick
- Progressive disclosure adapts governance complexity to treasury scale
- Integration examples show how third-party protocols (insurance, reputation, marketplaces) can compose with alliance treasury state

---

## Repository

https://github.com/elonfeng/eve-alliance-treasury
