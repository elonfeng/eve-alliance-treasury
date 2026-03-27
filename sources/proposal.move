/// Budget Proposal — multi-sig spending proposal with tiered approval thresholds.
///
/// Flow:
///   1. Any member calls create_proposal → BudgetProposal shared object created,
///      proposer auto-signs (signature_count = 1).
///   2. Other members call sign_proposal until signature_count >= required_count.
///   3. Any member calls execute_proposal → treasury::payout() transfers funds.
///      ProposalExecuted event is emitted as the on-chain audit record.
///
/// Tiered thresholds (from roles.move):
///   < 100 SUI  → 2 sigs    100-1000 SUI → 3 sigs    > 1000 SUI → 4 sigs
module alliance_treasury::proposal;

use std::string::String;
use sui::{
    clock::{Self, Clock},
    event,
    table::{Self, Table},
};
use alliance_treasury::{
    roles::{Self, RoleRegistry},
    treasury::{Self, AllianceTreasury},
};

// === Constants ===
const PROPOSAL_TTL_MS: u64 = 7 * 24 * 60 * 60 * 1000; // 7 days

// === Errors ===
const ENotMember:        u64 = 0;
const EAlreadySigned:    u64 = 1;
const ENotPending:       u64 = 2;
const EThresholdNotMet:  u64 = 3;
const EProposalExpired:  u64 = 4;
const EZeroAmount:       u64 = 5;
const EWrongTreasury:    u64 = 6;
const ENotExpired:       u64 = 7;

// === Enums ===
public enum ProposalStatus has copy, drop, store {
    Pending,
    Executed,
    Expired,
}

// === Structs ===

/// Shared object — one per spending request.
/// Lives on-chain as permanent audit record after execution.
public struct BudgetProposal has key {
    id: UID,
    treasury_id: ID,
    registry_id: ID,
    proposer: address,
    amount: u64,              // in MIST (1 SUI = 1_000_000_000 MIST)
    recipient: address,
    purpose: String,
    signatures: Table<address, bool>,
    signature_count: u64,
    required_count: u64,
    status: ProposalStatus,
    created_at: u64,
    expires_at: u64,
}

// === Events ===

public struct ProposalCreated has copy, drop {
    proposal_id: ID,
    treasury_id: ID,
    proposer: address,
    amount: u64,
    recipient: address,
    purpose: String,
    required_count: u64,
    expires_at: u64,
}

public struct ProposalSigned has copy, drop {
    proposal_id: ID,
    signer: address,
    signature_count: u64,
    required_count: u64,
}

public struct ProposalExecuted has copy, drop {
    proposal_id: ID,
    treasury_id: ID,
    executor: address,
    recipient: address,
    amount: u64,
}

public struct ProposalMarkedExpired has copy, drop {
    proposal_id: ID,
    marked_by: address,
}

// === Public Entry Functions ===

/// Any alliance member can submit a spending proposal.
/// Proposer automatically counts as the first signature.
public fun create_proposal(
    treasury: &AllianceTreasury,
    registry: &RoleRegistry,
    amount: u64,
    recipient: address,
    purpose: String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(roles::is_member(registry, ctx.sender()), ENotMember);
    assert!(amount > 0, EZeroAmount);

    let required_count = roles::required_signatures(amount);
    let now = clock::timestamp_ms(clock);
    let expires_at = now + PROPOSAL_TTL_MS;

    let mut proposal = BudgetProposal {
        id: object::new(ctx),
        treasury_id: object::id(treasury),
        registry_id: object::id(registry),
        proposer: ctx.sender(),
        amount,
        recipient,
        purpose,
        signatures: table::new(ctx),
        signature_count: 0,
        required_count,
        status: ProposalStatus::Pending,
        created_at: now,
        expires_at,
    };

    // Auto-sign: proposer counts as first signature
    table::add(&mut proposal.signatures, ctx.sender(), true);
    proposal.signature_count = 1;

    event::emit(ProposalCreated {
        proposal_id: object::id(&proposal),
        treasury_id: object::id(treasury),
        proposer: ctx.sender(),
        amount,
        recipient,
        purpose: proposal.purpose,
        required_count,
        expires_at,
    });

    transfer::share_object(proposal);
}

/// Alliance member signs an existing proposal.
/// Each address can only sign once.
public fun sign_proposal(
    proposal: &mut BudgetProposal,
    registry: &RoleRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(proposal.status == ProposalStatus::Pending, ENotPending);
    assert!(clock::timestamp_ms(clock) <= proposal.expires_at, EProposalExpired);
    assert!(roles::is_member(registry, ctx.sender()), ENotMember);
    assert!(!table::contains(&proposal.signatures, ctx.sender()), EAlreadySigned);

    table::add(&mut proposal.signatures, ctx.sender(), true);
    proposal.signature_count = proposal.signature_count + 1;

    event::emit(ProposalSigned {
        proposal_id: object::id(proposal),
        signer: ctx.sender(),
        signature_count: proposal.signature_count,
        required_count: proposal.required_count,
    });
}

/// Execute a proposal once the signature threshold is met.
/// Triggers treasury::payout() which transfers SUI to recipient.
/// ProposalExecuted event serves as the immutable audit record.
public fun execute_proposal(
    proposal: &mut BudgetProposal,
    treasury: &mut AllianceTreasury,
    registry: &RoleRegistry,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(proposal.status == ProposalStatus::Pending, ENotPending);
    assert!(clock::timestamp_ms(clock) <= proposal.expires_at, EProposalExpired);
    assert!(roles::is_member(registry, ctx.sender()), ENotMember);
    assert!(object::id(treasury) == proposal.treasury_id, EWrongTreasury);
    assert!(proposal.signature_count >= proposal.required_count, EThresholdNotMet);

    proposal.status = ProposalStatus::Executed;

    let proposal_id = object::id(proposal);
    let amount    = proposal.amount;
    let recipient = proposal.recipient;

    // Calls package-internal payout — only accessible within alliance_treasury package
    treasury::payout(treasury, amount, recipient, proposal_id, ctx);

    event::emit(ProposalExecuted {
        proposal_id,
        treasury_id: object::id(treasury),
        executor: ctx.sender(),
        recipient,
        amount,
    });
}

/// Mark an expired proposal as Expired (cleanup / clarity).
public fun mark_expired(
    proposal: &mut BudgetProposal,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(proposal.status == ProposalStatus::Pending, ENotPending);
    assert!(clock::timestamp_ms(clock) > proposal.expires_at, ENotExpired);
    proposal.status = ProposalStatus::Expired;
    event::emit(ProposalMarkedExpired {
        proposal_id: object::id(proposal),
        marked_by: ctx.sender(),
    });
}

// === View Functions ===

public fun is_pending(proposal: &BudgetProposal): bool {
    proposal.status == ProposalStatus::Pending
}

public fun is_executed(proposal: &BudgetProposal): bool {
    proposal.status == ProposalStatus::Executed
}

public fun has_signed(proposal: &BudgetProposal, addr: address): bool {
    table::contains(&proposal.signatures, addr)
}

public fun signature_count(proposal: &BudgetProposal): u64 {
    proposal.signature_count
}

public fun required_count(proposal: &BudgetProposal): u64 {
    proposal.required_count
}

public fun amount(proposal: &BudgetProposal): u64 {
    proposal.amount
}

public fun recipient(proposal: &BudgetProposal): address {
    proposal.recipient
}

public fun proposer(proposal: &BudgetProposal): address {
    proposal.proposer
}

public fun status(proposal: &BudgetProposal): ProposalStatus {
    proposal.status
}
