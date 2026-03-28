/// Policy Agent — on-chain autonomous governance participant.
///
/// An agent-native approach to treasury governance: instead of calling an
/// external AI API, the agent embodies deterministic, auditable rules as
/// composable "skills" that can be enabled/disabled per alliance.
///
/// Skills (bitmask, combinable):
///   AUTO_APPROVE   = 1  — auto-sign proposals below max_auto_amount
///   RATE_LIMIT     = 2  — enforce daily spending cap
///   TRUSTED_LIST   = 4  — only auto-sign for trusted recipients
///   BALANCE_GUARD  = 8  — block if treasury balance would drop below reserve
///   COOLDOWN       = 16 — enforce cooldown between payouts to same recipient
///
/// Progressive disclosure: the agent adapts governance complexity based on
/// treasury state. Small treasuries get simple auto-approve; large treasuries
/// activate rate limiting and balance guards automatically.
///
/// Design philosophy: "Agent value is not about being AI — it's about
/// autonomous, trustworthy, tamper-proof governance execution."
module alliance_treasury::policy_agent;

use sui::{
    clock::{Self, Clock},
    event,
    table::{Self, Table},
};
use alliance_treasury::treasury::{Self, AdminCap, AllianceTreasury};

// === Skill Constants (bitmask) ===
const SKILL_AUTO_APPROVE:  u8 = 1;
const SKILL_RATE_LIMIT:    u8 = 2;
const SKILL_TRUSTED_LIST:  u8 = 4;
const SKILL_BALANCE_GUARD: u8 = 8;
const SKILL_COOLDOWN:      u8 = 16;

// === Time Constants ===
const MS_PER_DAY: u64 = 86_400_000;

// === Errors ===
const EWrongTreasury:        u64 = 0;
const EAmountTooLarge:       u64 = 1;
const EDailyLimitExceeded:   u64 = 2;
const ERecipientNotTrusted:  u64 = 3;
const EBalanceTooLow:        u64 = 4;
const ECooldownActive:       u64 = 5;
const EAgentDisabled:        u64 = 6;
const EAlreadyTrusted:       u64 = 8;
const ENotTrusted:           u64 = 9;

// === Structs ===

/// Shared object — the alliance's on-chain policy agent.
/// Configurable by admin, acts as an autonomous signer.
public struct PolicyAgent has key {
    id: UID,
    treasury_id: ID,
    enabled: bool,
    active_skills: u8,            // bitmask of enabled skills

    // Skill configs
    max_auto_amount: u64,         // AUTO_APPROVE: max amount (MIST) for auto-sign
    daily_limit: u64,             // RATE_LIMIT: max daily auto-signed total (MIST)
    min_balance_reserve: u64,     // BALANCE_GUARD: min treasury balance to maintain
    cooldown_ms: u64,             // COOLDOWN: min time between payouts to same recipient

    // Runtime state
    daily_spent: u64,             // total auto-signed today
    last_reset_day: u64,          // day number of last reset (timestamp_ms / MS_PER_DAY)
    trusted_recipients: Table<address, bool>,
    recent_payouts: Table<address, u64>,  // recipient → last payout timestamp
    total_auto_signed: u64,       // lifetime count of auto-signed proposals
    total_rejected: u64,          // lifetime count of rejected evaluations
}

// === Events ===

public struct AgentCreated has copy, drop {
    agent_id: ID,
    treasury_id: ID,
    active_skills: u8,
    creator: address,
}

public struct AgentEvaluated has copy, drop {
    agent_id: ID,
    proposal_amount: u64,
    recipient: address,
    approved: bool,
    rejection_reason: u8,  // 0=approved, 1=amount, 2=daily_limit, 3=untrusted, 4=balance, 5=cooldown
}

public struct AgentConfigUpdated has copy, drop {
    agent_id: ID,
    active_skills: u8,
    max_auto_amount: u64,
    daily_limit: u64,
    updated_by: address,
}

public struct TrustedRecipientAdded has copy, drop {
    agent_id: ID,
    recipient: address,
}

public struct TrustedRecipientRemoved has copy, drop {
    agent_id: ID,
    recipient: address,
}

// === Create ===

/// Create a PolicyAgent for an alliance treasury. Admin only.
/// Starts with AUTO_APPROVE + RATE_LIMIT enabled (skills = 3).
public fun create_agent(
    cap: &AdminCap,
    max_auto_amount: u64,
    daily_limit: u64,
    ctx: &mut TxContext,
) {
    let agent = PolicyAgent {
        id: object::new(ctx),
        treasury_id: treasury::treasury_id(cap),
        enabled: true,
        active_skills: SKILL_AUTO_APPROVE | SKILL_RATE_LIMIT, // default: 1 + 2 = 3

        max_auto_amount,
        daily_limit,
        min_balance_reserve: 0,
        cooldown_ms: 0,

        daily_spent: 0,
        last_reset_day: 0,
        trusted_recipients: table::new(ctx),
        recent_payouts: table::new(ctx),
        total_auto_signed: 0,
        total_rejected: 0,
    };
    event::emit(AgentCreated {
        agent_id: object::id(&agent),
        treasury_id: agent.treasury_id,
        active_skills: agent.active_skills,
        creator: ctx.sender(),
    });
    transfer::share_object(agent);
}

// === Core: Evaluate & Auto-Sign ===

/// Evaluate whether the agent would approve a proposal.
/// Returns true if all active skill checks pass.
/// Does NOT modify state — use auto_sign_proposal() to actually sign.
public fun evaluate(
    agent: &PolicyAgent,
    treasury: &AllianceTreasury,
    amount: u64,
    recipient: address,
    clock: &Clock,
): bool {
    if (!agent.enabled) return false;

    let today = clock::timestamp_ms(clock) / MS_PER_DAY;

    // Skill 1: AUTO_APPROVE — check amount
    if (has_skill(agent, SKILL_AUTO_APPROVE)) {
        if (amount > agent.max_auto_amount) return false;
    };

    // Skill 2: RATE_LIMIT — check daily cap
    if (has_skill(agent, SKILL_RATE_LIMIT)) {
        let spent = if (today != agent.last_reset_day) 0 else agent.daily_spent;
        if (spent + amount > agent.daily_limit) return false;
    };

    // Skill 3: TRUSTED_LIST — check recipient
    if (has_skill(agent, SKILL_TRUSTED_LIST)) {
        if (!table::contains(&agent.trusted_recipients, recipient)) return false;
    };

    // Skill 4: BALANCE_GUARD — check treasury won't go below reserve
    if (has_skill(agent, SKILL_BALANCE_GUARD)) {
        let balance = treasury::get_balance(treasury);
        if (balance < amount + agent.min_balance_reserve) return false;
    };

    // Skill 5: COOLDOWN — check last payout to this recipient
    if (has_skill(agent, SKILL_COOLDOWN) && agent.cooldown_ms > 0) {
        if (table::contains(&agent.recent_payouts, recipient)) {
            let last_payout = *table::borrow(&agent.recent_payouts, recipient);
            if (clock::timestamp_ms(clock) < last_payout + agent.cooldown_ms) return false;
        };
    };

    true
}

/// Auto-sign a proposal via the agent. Called by proposal module.
/// Updates agent state (daily_spent, recent_payouts, counters).
/// Aborts if evaluation fails.
public(package) fun auto_sign_proposal(
    agent: &mut PolicyAgent,
    treasury: &AllianceTreasury,
    amount: u64,
    recipient: address,
    clock: &Clock,
) {
    assert!(agent.enabled, EAgentDisabled);

    let today = clock::timestamp_ms(clock) / MS_PER_DAY;
    let now = clock::timestamp_ms(clock);

    // Reset daily counter if new day
    if (today != agent.last_reset_day) {
        agent.daily_spent = 0;
        agent.last_reset_day = today;
    };

    // Run all skill checks with specific error codes
    if (has_skill(agent, SKILL_AUTO_APPROVE)) {
        assert!(amount <= agent.max_auto_amount, EAmountTooLarge);
    };
    if (has_skill(agent, SKILL_RATE_LIMIT)) {
        assert!(agent.daily_spent + amount <= agent.daily_limit, EDailyLimitExceeded);
    };
    if (has_skill(agent, SKILL_TRUSTED_LIST)) {
        assert!(table::contains(&agent.trusted_recipients, recipient), ERecipientNotTrusted);
    };
    if (has_skill(agent, SKILL_BALANCE_GUARD)) {
        let balance = treasury::get_balance(treasury);
        assert!(balance >= amount + agent.min_balance_reserve, EBalanceTooLow);
    };
    if (has_skill(agent, SKILL_COOLDOWN) && agent.cooldown_ms > 0) {
        if (table::contains(&agent.recent_payouts, recipient)) {
            let last_payout = *table::borrow(&agent.recent_payouts, recipient);
            assert!(now >= last_payout + agent.cooldown_ms, ECooldownActive);
        };
    };

    // All checks passed — update state
    agent.daily_spent = agent.daily_spent + amount;
    agent.total_auto_signed = agent.total_auto_signed + 1;

    // Update cooldown tracker
    if (table::contains(&agent.recent_payouts, recipient)) {
        *table::borrow_mut(&mut agent.recent_payouts, recipient) = now;
    } else {
        table::add(&mut agent.recent_payouts, recipient, now);
    };

    event::emit(AgentEvaluated {
        agent_id: object::id(agent),
        proposal_amount: amount,
        recipient,
        approved: true,
        rejection_reason: 0,
    });
}

// === Admin Config ===

/// Enable or disable the agent entirely.
public fun set_enabled(
    agent: &mut PolicyAgent,
    cap: &AdminCap,
    enabled: bool,
) {
    assert!(treasury::treasury_id(cap) == agent.treasury_id, EWrongTreasury);
    agent.enabled = enabled;
}

/// Update active skills bitmask. Admin only.
public fun set_skills(
    agent: &mut PolicyAgent,
    cap: &AdminCap,
    skills: u8,
    ctx: &mut TxContext,
) {
    assert!(treasury::treasury_id(cap) == agent.treasury_id, EWrongTreasury);
    agent.active_skills = skills;
    event::emit(AgentConfigUpdated {
        agent_id: object::id(agent),
        active_skills: skills,
        max_auto_amount: agent.max_auto_amount,
        daily_limit: agent.daily_limit,
        updated_by: ctx.sender(),
    });
}

/// Update agent parameters. Admin only.
public fun configure(
    agent: &mut PolicyAgent,
    cap: &AdminCap,
    max_auto_amount: u64,
    daily_limit: u64,
    min_balance_reserve: u64,
    cooldown_ms: u64,
    ctx: &mut TxContext,
) {
    assert!(treasury::treasury_id(cap) == agent.treasury_id, EWrongTreasury);
    agent.max_auto_amount = max_auto_amount;
    agent.daily_limit = daily_limit;
    agent.min_balance_reserve = min_balance_reserve;
    agent.cooldown_ms = cooldown_ms;
    event::emit(AgentConfigUpdated {
        agent_id: object::id(agent),
        active_skills: agent.active_skills,
        max_auto_amount,
        daily_limit,
        updated_by: ctx.sender(),
    });
}

/// Add a trusted recipient. Admin only.
public fun add_trusted_recipient(
    agent: &mut PolicyAgent,
    cap: &AdminCap,
    recipient: address,
) {
    assert!(treasury::treasury_id(cap) == agent.treasury_id, EWrongTreasury);
    assert!(!table::contains(&agent.trusted_recipients, recipient), EAlreadyTrusted);
    table::add(&mut agent.trusted_recipients, recipient, true);
    event::emit(TrustedRecipientAdded {
        agent_id: object::id(agent),
        recipient,
    });
}

/// Remove a trusted recipient. Admin only.
public fun remove_trusted_recipient(
    agent: &mut PolicyAgent,
    cap: &AdminCap,
    recipient: address,
) {
    assert!(treasury::treasury_id(cap) == agent.treasury_id, EWrongTreasury);
    assert!(table::contains(&agent.trusted_recipients, recipient), ENotTrusted);
    table::remove(&mut agent.trusted_recipients, recipient);
    event::emit(TrustedRecipientRemoved {
        agent_id: object::id(agent),
        recipient,
    });
}

// === View Functions ===

public fun is_enabled(agent: &PolicyAgent): bool { agent.enabled }
public fun active_skills(agent: &PolicyAgent): u8 { agent.active_skills }
public fun max_auto_amount(agent: &PolicyAgent): u64 { agent.max_auto_amount }
public fun daily_limit(agent: &PolicyAgent): u64 { agent.daily_limit }
public fun daily_spent(agent: &PolicyAgent): u64 { agent.daily_spent }
public fun min_balance_reserve(agent: &PolicyAgent): u64 { agent.min_balance_reserve }
public fun cooldown_ms(agent: &PolicyAgent): u64 { agent.cooldown_ms }
public fun total_auto_signed(agent: &PolicyAgent): u64 { agent.total_auto_signed }
public fun total_rejected(agent: &PolicyAgent): u64 { agent.total_rejected }
public fun is_trusted(agent: &PolicyAgent, addr: address): bool {
    table::contains(&agent.trusted_recipients, addr)
}
public fun treasury_id(agent: &PolicyAgent): ID { agent.treasury_id }

fun has_skill(agent: &PolicyAgent, skill: u8): bool {
    (agent.active_skills & skill) != 0
}

// Skill constant accessors for tests and external modules
public fun skill_auto_approve(): u8 { SKILL_AUTO_APPROVE }
public fun skill_rate_limit(): u8 { SKILL_RATE_LIMIT }
public fun skill_trusted_list(): u8 { SKILL_TRUSTED_LIST }
public fun skill_balance_guard(): u8 { SKILL_BALANCE_GUARD }
public fun skill_cooldown(): u8 { SKILL_COOLDOWN }
