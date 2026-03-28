# Architecture -- Alliance Multi-Sig Treasury

Technical deep-dive into the system design, module dependencies, security model, and integration patterns.

---

## System Architecture

The system is organized into three layers. Data flows upward from on-chain state through the indexer backend to the frontend. Transactions flow downward from user actions through the dApp to the Sui network.

```
                         +---------------------------+
                         |      FRONTEND (dApp)      |
                         |                           |
                         |  React + @mysten/dapp-kit |
                         |  Wallet adapter           |
                         |  Proposal dashboard       |
                         |  Role management UI       |
                         |  Audit trail viewer       |
                         +------+----------+---------+
                                |          |
                    REST queries |          | Sui transactions
                    (read path) |          | (write path)
                                v          v
                  +-------------+---+  +---+----------------+
                  |    BACKEND      |  |   Sui Network      |
                  |                 |  |   (Testnet/Mainnet) |
                  |  Express API    |  |                     |
                  |  SQLite store   |  +---+----------------+
                  |  Event indexer  |      ^
                  +--------+--------+      |
                           |               |
              Event polling|               | PTB submissions
              (10s/30s)    |               | from dApp wallet
                           v               |
                  +--------+---------------+---+
                  |     ON-CHAIN CONTRACTS      |
                  |     (alliance_treasury)     |
                  |                             |
                  |  Shared objects:            |
                  |    AllianceTreasury         |
                  |    RoleRegistry             |
                  |    BudgetProposal (per req) |
                  |    PolicyAgent              |
                  |    MemberWhitelist          |
                  |                             |
                  |  Owned objects:             |
                  |    AdminCap                 |
                  +-----------------------------+
```

### Data Flow: Read Path

```
User opens dashboard
  --> dApp calls GET /api/proposals
    --> Backend queries SQLite
      --> SQLite populated by indexer
        --> Indexer polls SuiClient.queryEvents()
          --> Sui full node returns on-chain events
```

### Data Flow: Write Path

```
User clicks "Sign Proposal"
  --> dApp builds PTB via @mysten/sui SDK
    --> Wallet signs transaction
      --> Transaction submitted to Sui network
        --> Move VM executes proposal::sign_proposal()
          --> On-chain event emitted (ProposalSigned)
            --> Indexer picks up event on next poll cycle
              --> SQLite updated
                --> Next GET /api/proposals reflects new signature
```

---

## Module Dependency Graph

```
+----------------------+
| integration_examples |  (read-only, composes all modules)
+---+--+--+--+---------+
    |  |  |  |
    v  v  v  v
+----------+  +-------+  +----------+  +-----------+
| treasury |  | roles |  | proposal |  | gate_sync |
+----+-----+  +---+---+  +----+-----+  +-----+-----+
     ^            ^            |  |           ^
     |            |            |  |           |
     |            +------------+  |           |
     |         reads registry     |           |
     |                            |           |
     +------- calls payout -------+           |
     |       (public(package))                |
     |                                        |
     |   +--------------+                     |
     +---| policy_agent |                     |
     ^   +------+-------+                     |
     |          |                              |
     |   calls auto_sign_proposal             |
     |   (public(package))                    |
     |          |                              |
     +--- reads treasury balance              |
                                               |
     AdminCap flows to: roles, gate_sync,      |
                        policy_agent ----------+
```

### Dependency Rules

| Module | Depends On | Depended On By |
|--------|-----------|----------------|
| `treasury` | (none) | proposal, policy_agent, gate_sync, integration_examples |
| `roles` | treasury (AdminCap type) | proposal, integration_examples |
| `proposal` | treasury, roles, policy_agent | integration_examples |
| `gate_sync` | treasury (AdminCap type), world::gate, world::character | integration_examples |
| `policy_agent` | treasury | proposal |
| `integration_examples` | treasury, roles, proposal, policy_agent, gate_sync | (none -- leaf module) |

The `treasury` module is the root dependency. It defines both the vault (`AllianceTreasury`) and the admin capability (`AdminCap`) that flows through the entire system.

---

## Policy Agent Design Philosophy

### Why Agent-Native, Not AI-Dependent

Most "AI agent" implementations in crypto are wrappers around external API calls. They are:

- **Non-deterministic**: Same inputs can produce different outputs depending on model state.
- **Opaque**: Members cannot verify why a decision was made.
- **Fragile**: If the API goes down, governance halts.
- **Centralized**: Whoever controls the API key controls the agent.

The Policy Agent takes the opposite approach. Every rule is encoded as a Move function that reads only on-chain state. The evaluation is:

1. **Deterministic** -- Given the same chain state and clock timestamp, the agent always produces the same result.
2. **Auditable** -- Every evaluation emits an `AgentEvaluated` event with an explicit rejection reason code (0=approved, 1=amount, 2=daily_limit, 3=untrusted, 4=balance, 5=cooldown).
3. **Available** -- The agent exists as a shared object on Sui. It cannot go offline.
4. **Non-custodial** -- The agent never holds funds. It adds one signature toward the multi-sig threshold. Humans still must participate.

### The Agent as a Governance Participant

The Policy Agent is not a replacement for human signers. It is one participant in the multi-sig quorum:

```
Proposal: 500 SUI payment to @0xFF
Required signatures: 3

  Signer 1: Commander (human)     -- signed
  Signer 2: PolicyAgent (on-chain) -- auto-signed (all skill checks passed)
  Signer 3: Treasurer (human)     -- signed

  Threshold met (3/3). Execute.
```

This design reduces friction for routine payouts (the agent handles one of the required signatures automatically) while preserving human oversight (at least N-1 humans must still approve).

---

## Skill System Design

### Bitmask Architecture

Skills use a 5-bit bitmask stored as a `u8`:

```
Bit:   4       3       2       1       0
     +-------+-------+-------+-------+-------+
     |COOLDOWN|BALANCE|TRUSTED| RATE  | AUTO  |
     | GUARD  | GUARD | LIST  | LIMIT |APPROVE|
     +-------+-------+-------+-------+-------+

Examples:
  00011 (3)  = AUTO_APPROVE + RATE_LIMIT
  00111 (7)  = AUTO_APPROVE + RATE_LIMIT + TRUSTED_LIST
  11111 (31) = All skills active
```

### Composability

Each skill is an independent check. The evaluation function runs all active skills in sequence:

```
evaluate(agent, treasury, amount, recipient, clock):
  if SKILL_AUTO_APPROVE active:
    check amount <= max_auto_amount         --> fail: reason 1
  if SKILL_RATE_LIMIT active:
    check daily_spent + amount <= daily_limit --> fail: reason 2
  if SKILL_TRUSTED_LIST active:
    check recipient in trusted_recipients   --> fail: reason 3
  if SKILL_BALANCE_GUARD active:
    check balance >= amount + reserve       --> fail: reason 4
  if SKILL_COOLDOWN active:
    check now >= last_payout + cooldown_ms  --> fail: reason 5
  all passed --> approved (reason 0)
```

Adding a new skill requires:

1. Define a new bit constant (e.g., `SKILL_NEW = 32`)
2. Add the check to `evaluate()` and `auto_sign_proposal()`
3. Add a config field to `PolicyAgent` struct

Existing skills are unaffected because each check is gated by its own bitmask test.

### State Management

The agent maintains runtime state that resets on boundaries:

| State Field | Reset Condition | Purpose |
|-------------|-----------------|---------|
| `daily_spent` | New day (timestamp_ms / MS_PER_DAY changes) | Rate limiting |
| `recent_payouts` | Never (grows monotonically, per recipient) | Cooldown enforcement |
| `total_auto_signed` | Never (lifetime counter) | Analytics |
| `total_rejected` | Never (lifetime counter) | Analytics |

---

## Progressive Disclosure

The system adapts governance complexity based on alliance needs rather than forcing maximum security on every treasury:

### Stage 1: New Alliance (< 100 SUI)

```
Skills: AUTO_APPROVE + RATE_LIMIT (bitmask = 3)
Config: max_auto_amount = 50 SUI, daily_limit = 100 SUI

Behavior: Agent auto-signs small routine payouts. Two human signatures
suffice for anything under 100 SUI. Minimal overhead for a small group.
```

### Stage 2: Growing Alliance (100-1000 SUI)

```
Skills: + TRUSTED_LIST (bitmask = 7)
Config: Add trusted recipients for known operational addresses.

Behavior: Agent only auto-signs to pre-approved addresses. Unknown
recipients require full human-only multi-sig. Prevents social engineering.
```

### Stage 3: Large War Chest (> 1000 SUI)

```
Skills: + BALANCE_GUARD + COOLDOWN (bitmask = 31)
Config: min_balance_reserve = 500 SUI, cooldown_ms = 3600000 (1 hour)

Behavior: Agent blocks any payout that would deplete the treasury below
reserve. Rapid successive payouts to the same address are throttled.
Maximum protection for high-value treasuries.
```

The admin transitions between stages by calling `set_skills()` and `configure()` -- no contract redeployment needed.

---

## PTB Atomic Execution Patterns

Programmable Transaction Blocks (PTBs) are the key mechanism for composing governance actions with in-game effects.

### Pattern 1: Payout + Gate Access (Primary Use Case)

```
PTB {
  // Step 1: Execute the approved proposal -- transfers SUI
  proposal::execute_proposal(proposal, treasury, registry, clock)

  // Step 2: Add the paid contractor to the gate whitelist
  gate_sync::whitelist_member(whitelist, admin_cap, new_member)
}
// Both succeed or both revert. No state where someone is paid but
// cannot access the gate, or has gate access but was not paid.
```

### Pattern 2: Role Update + Gate Sync

```
PTB {
  // Step 1: Promote member to Commander
  roles::update_role(registry, admin_cap, member, 5)  // Commander + Elder

  // Step 2: Ensure they are on the gate whitelist
  gate_sync::whitelist_member(whitelist, admin_cap, member)
}
```

### Pattern 3: Emergency Response

```
PTB {
  // Step 1: Freeze the treasury (stops all payouts)
  treasury::emergency_freeze(treasury)

  // Step 2: Remove compromised member from gate whitelist
  gate_sync::remove_from_whitelist(whitelist, admin_cap, compromised_addr)

  // Step 3: Remove from role registry
  roles::remove_member(registry, admin_cap, compromised_addr)
}
// Atomic: compromised member loses all access in one transaction.
```

### Why PTBs Matter for Governance

Without PTBs, the steps above would be separate transactions. Between Step 1 and Step 2, there is a window where state is inconsistent. An attacker could exploit that window (e.g., still having gate access after funds are frozen). PTBs eliminate this class of attack entirely.

---

## Event-Driven Indexing Architecture

The backend indexer bridges on-chain state to a queryable REST API.

```
+-------------------+     +-------------------+     +-------------------+
|   Sui Full Node   |     |   Event Indexer   |     |   SQLite Store    |
|                   |     |                   |     |                   |
| queryEvents(      | --> | processProposal   | --> | proposals table   |
|   MoveEventType,  |     |   Created()       |     | signatures table  |
|   cursor)         |     | processProposal   |     | payouts table     |
|                   |     |   Signed()        |     | killmails table   |
| KillMail events   | --> | processKillmail() | --> | jumps table       |
| JumpEvent data    | --> | processJump()     |     | cursors table     |
+-------------------+     +-------------------+     +-------------------+
```

### Cursor-Based Pagination

The indexer tracks its position in each event stream using a `cursors` table:

```sql
CREATE TABLE cursors (
  key TEXT PRIMARY KEY,     -- e.g., "treasury_events", "eve_killmails"
  tx_digest TEXT NOT NULL,
  event_seq TEXT NOT NULL
);
```

On each poll cycle:

1. Load cursor for the event stream
2. Call `queryEvents()` with cursor (or from beginning if no cursor)
3. Process each event (insert/update rows)
4. Save new cursor position

This ensures exactly-once processing even if the backend restarts.

### Polling Intervals

| Event Stream | Interval | Rationale |
|-------------|----------|-----------|
| Treasury events (proposal, payout, agent) | 10 seconds | Financial events need near-real-time visibility |
| EVE world events (KillMail, JumpEvent) | 30 seconds | Game events are less time-sensitive |

---

## Security Model

### Access Control Layers

```
Layer 1: Object Ownership (Sui runtime)
  AdminCap is an owned object. Only the holder's wallet can pass it
  to functions that require &AdminCap. This is enforced by the Sui
  runtime before Move code even executes.

Layer 2: public(package) Visibility (Move compiler)
  treasury::payout() is public(package). The Move compiler guarantees
  that only modules within alliance_treasury can call it. No external
  package can invoke payout regardless of what objects they hold.

Layer 3: Role-Based Checks (Application logic)
  proposal::sign_proposal() checks roles::is_member(registry, sender).
  Even if someone has access to the shared proposal object, they cannot
  sign without being in the RoleRegistry.

Layer 4: Multi-Sig Threshold (Application logic)
  execute_proposal() checks signature_count >= required_count.
  No single signer can trigger a payout regardless of their role.

Layer 5: Policy Agent Guards (Application logic)
  If the agent is configured with BALANCE_GUARD, it will refuse to
  sign any proposal that would deplete the treasury below the reserve.
  This acts as an automated circuit breaker.
```

### Capability Pattern

The `AdminCap` struct follows the Sui Capability pattern:

```move
public struct AdminCap has key, store {
    id: UID,
    treasury_id: ID,  // scoped to one treasury
}
```

Key properties:

- **Scoped**: Each AdminCap references a specific `treasury_id`. It cannot be used to administrate a different treasury.
- **Transferable**: The `store` ability allows the AdminCap to be transferred to a new admin (e.g., leadership change).
- **Unforgeable**: Only `create_treasury()` mints an AdminCap. There is no public constructor.
- **One-to-one**: Each treasury creates exactly one AdminCap at creation time.

### No Single Point of Failure

| Attack Vector | Mitigation |
|--------------|------------|
| Admin disappears with AdminCap | Treasury funds remain safe. Proposals can still be created and signed by members. Only admin-only actions (unfreeze, role changes) are blocked. |
| Admin goes rogue | Any member can emergency freeze the treasury. Freeze does not require AdminCap. |
| Single member compromised | Multi-sig threshold requires 2-4 signatures. One compromised key cannot drain funds. |
| Policy Agent misconfigured | Agent only provides one signature. Humans must still sign (N-1 of N required). Admin can disable agent via `set_enabled(false)`. |
| External contract tries to drain vault | `public(package)` on `payout()` prevents any external contract from calling it. Compiler-enforced. |

---

## Integration Patterns for Third-Party Builders

The `integration_examples` module demonstrates read-only composition patterns. All alliance treasury state is queryable via public view functions.

### Pattern 1: Gate Access on Treasury Membership

```move
// Your module can check if a player is in an alliance before granting access
public fun my_gate_check(registry: &RoleRegistry, player: address): bool {
    alliance_treasury::roles::is_member(registry, player)
}
```

### Pattern 2: Risk Assessment on Treasury Health

```move
// Insurance or lending protocols can assess alliance solvency
public fun assess_risk(treasury: &AllianceTreasury, coverage: u64): bool {
    let balance = alliance_treasury::treasury::get_balance(treasury);
    let frozen = alliance_treasury::treasury::is_frozen(treasury);
    !frozen && balance >= coverage * 2
}
```

### Pattern 3: Role-Based Perks

```move
// Marketplace can offer discounts to alliance elders
public fun get_discount(registry: &RoleRegistry, buyer: address): u64 {
    if (alliance_treasury::roles::has_role(registry, buyer, 4)) {
        10  // 10% discount for elders
    } else if (alliance_treasury::roles::is_member(registry, buyer)) {
        5   // 5% discount for any member
    } else {
        0
    }
}
```

### Pattern 4: Pre-Flight Agent Check

```move
// Check if the agent would approve before submitting (saves gas on rejection)
public fun should_submit_proposal(
    agent: &PolicyAgent,
    treasury: &AllianceTreasury,
    amount: u64,
    recipient: address,
    clock: &Clock,
): bool {
    alliance_treasury::policy_agent::evaluate(agent, treasury, amount, recipient, clock)
}
```

### Available View Functions

| Module | Function | Returns |
|--------|----------|---------|
| `treasury` | `get_balance(treasury)` | `u64` -- current balance in MIST |
| `treasury` | `is_frozen(treasury)` | `bool` -- emergency freeze status |
| `treasury` | `total_deposited(treasury)` | `u64` -- lifetime deposits |
| `treasury` | `total_paid_out(treasury)` | `u64` -- lifetime payouts |
| `roles` | `is_member(registry, addr)` | `bool` -- membership check |
| `roles` | `has_role(registry, addr, role)` | `bool` -- specific role check |
| `roles` | `get_role(registry, addr)` | `u8` -- full role bitmask |
| `roles` | `member_count(registry)` | `u64` -- total members |
| `roles` | `required_signatures(amount)` | `u64` -- threshold for amount |
| `proposal` | `is_pending(proposal)` | `bool` |
| `proposal` | `is_executed(proposal)` | `bool` |
| `proposal` | `has_signed(proposal, addr)` | `bool` |
| `proposal` | `signature_count(proposal)` | `u64` |
| `proposal` | `required_count(proposal)` | `u64` |
| `policy_agent` | `is_enabled(agent)` | `bool` |
| `policy_agent` | `evaluate(agent, treasury, amount, recipient, clock)` | `bool` |
| `policy_agent` | `is_trusted(agent, addr)` | `bool` |
| `policy_agent` | `daily_spent(agent)` | `u64` |
| `gate_sync` | `is_whitelisted(whitelist, addr)` | `bool` |
| `gate_sync` | `member_count(whitelist)` | `u64` |

All view functions are `public` (not `public(package)`) and take immutable references (`&`). Any on-chain module can call them without permission.
