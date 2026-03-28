/// Integration Examples — shows how external protocols can compose with
/// the alliance treasury contracts using only public view functions.
///
/// All functions here are read-only queries. They demonstrate patterns
/// that other on-chain modules would use to gate their own logic on
/// alliance treasury state (membership, balance, policy, whitelist).
module alliance_treasury::integration_examples;

use sui::clock::Clock;
use alliance_treasury::{
    treasury::AllianceTreasury,
    roles::RoleRegistry,
    proposal::BudgetProposal,
    policy_agent::PolicyAgent,
    gate_sync::MemberWhitelist,
};

// -------------------------------------------------------------------------
// 1. Insurance protocol integration
//
// An insurance contract checks that the treasury is solvent and the
// applicant is a registered alliance member before issuing a policy.
// The insurer can also size premiums based on treasury health.
// -------------------------------------------------------------------------

/// Returns true if the treasury has enough balance to back a coverage
/// amount and the applicant is an active alliance member.
public fun can_insure(
    treasury: &AllianceTreasury,
    registry: &RoleRegistry,
    applicant: address,
    coverage_amount: u64,
): bool {
    // Reject if the treasury is frozen (emergency state).
    if (alliance_treasury::treasury::is_frozen(treasury)) return false;

    // Applicant must be a registered alliance member.
    if (!alliance_treasury::roles::is_member(registry, applicant)) return false;

    // Treasury balance must be at least 2x the coverage so the alliance
    // remains solvent even after a full payout.
    let balance = alliance_treasury::treasury::get_balance(treasury);
    balance >= coverage_amount * 2
}

// -------------------------------------------------------------------------
// 2. Reputation query
//
// Another protocol (e.g. a marketplace or lending protocol) checks
// whether an address holds a specific alliance role. This lets external
// contracts offer perks to commanders, treasurers, or elders.
// -------------------------------------------------------------------------

/// Returns true if `addr` is a member with the ELDER role (bitmask 4).
/// External contracts can use this to gate access to high-trust actions.
public fun is_elder_member(
    registry: &RoleRegistry,
    addr: address,
): bool {
    alliance_treasury::roles::has_role(registry, addr, alliance_treasury::roles::role_elder())
}

/// Returns the full role bitmask for an address, or 0 if not a member.
/// Callers can inspect individual bits: COMMANDER=1, TREASURER=2,
/// ELDER=4, AUDITOR=8.
public fun query_member_role(
    registry: &RoleRegistry,
    addr: address,
): u8 {
    alliance_treasury::roles::get_role(registry, addr)
}

// -------------------------------------------------------------------------
// 3. Agent policy check
//
// Before submitting a proposal, a frontend or composing contract can
// predict whether the PolicyAgent will auto-approve it. This avoids
// wasting gas on proposals that the agent would reject.
// -------------------------------------------------------------------------

/// Returns true if the agent is active and would auto-approve a
/// proposal of the given amount to the given recipient right now.
public fun would_agent_approve(
    agent: &PolicyAgent,
    treasury: &AllianceTreasury,
    amount: u64,
    recipient: address,
    clock: &Clock,
): bool {
    // Quick exit: if the agent is disabled it will never sign.
    if (!alliance_treasury::policy_agent::is_enabled(agent)) return false;

    // Full evaluation against all active skills (read-only).
    alliance_treasury::policy_agent::evaluate(agent, treasury, amount, recipient, clock)
}

/// Returns true if a proposal already has enough signatures to execute.
/// Useful for UIs or bots that monitor proposals and trigger execution.
public fun is_ready_to_execute(proposal: &BudgetProposal): bool {
    alliance_treasury::proposal::is_pending(proposal)
        && alliance_treasury::proposal::signature_count(proposal)
            >= alliance_treasury::proposal::required_count(proposal)
}

// -------------------------------------------------------------------------
// 4. Gate access verification
//
// Before attempting a jump (which costs gas and may abort), another
// module or off-chain client can check whitelist status first.
// -------------------------------------------------------------------------

/// Returns true if the pilot address is on the alliance gate whitelist.
/// Call this before issue_member_permit to avoid a wasted transaction.
public fun can_jump(
    whitelist: &MemberWhitelist,
    pilot: address,
): bool {
    alliance_treasury::gate_sync::is_whitelisted(whitelist, pilot)
}

/// Returns the number of whitelisted pilots. Useful for analytics
/// dashboards or protocols that scale fees by alliance size.
public fun alliance_gate_size(whitelist: &MemberWhitelist): u64 {
    alliance_treasury::gate_sync::member_count(whitelist)
}
