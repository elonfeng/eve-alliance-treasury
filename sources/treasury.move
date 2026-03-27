/// Alliance Treasury — core vault module.
/// Holds SUI funds for an alliance. Funds can only be released
/// via an approved multi-sig proposal (proposal.move calls payout).
module alliance_treasury::treasury;

use std::string::String;
use sui::{
    balance::{Self, Balance},
    coin::{Self, Coin},
    event,
    sui::SUI,
};

// === Errors ===
const ETreasuryFrozen:      u64 = 0;
const EInsufficientBalance: u64 = 1;
const EZeroAmount:          u64 = 2;
const EWrongTreasury:       u64 = 3;

// === Structs ===

/// Shared object — the alliance's on-chain vault.
public struct AllianceTreasury has key {
    id: UID,
    name: String,
    balance: Balance<SUI>,
    total_deposited: u64,
    total_paid_out: u64,
    frozen: bool,
}

/// Owned capability — held by the deployer / admin.
/// Required for admin-only operations (unfreeze, role management).
public struct AdminCap has key, store {
    id: UID,
    treasury_id: ID,
}

// === Events ===

public struct TreasuryCreated has copy, drop {
    treasury_id: ID,
    name: String,
    creator: address,
}

public struct Deposited has copy, drop {
    treasury_id: ID,
    depositor: address,
    amount: u64,
    new_balance: u64,
}

public struct PaidOut has copy, drop {
    treasury_id: ID,
    recipient: address,
    amount: u64,
    proposal_id: ID,
}

public struct EmergencyFrozen has copy, drop {
    treasury_id: ID,
    frozen_by: address,
}

public struct Unfrozen has copy, drop {
    treasury_id: ID,
    unfrozen_by: address,
}

// === Public Entry Functions ===

/// Create a new AllianceTreasury. Caller receives AdminCap.
/// Anyone can create their own treasury — one per alliance.
public fun create_treasury(name: String, ctx: &mut TxContext) {
    let treasury = AllianceTreasury {
        id: object::new(ctx),
        name,
        balance: balance::zero<SUI>(),
        total_deposited: 0,
        total_paid_out: 0,
        frozen: false,
    };
    let treasury_id = object::id(&treasury);
    let admin_cap = AdminCap {
        id: object::new(ctx),
        treasury_id,
    };
    event::emit(TreasuryCreated {
        treasury_id,
        name: treasury.name,
        creator: ctx.sender(),
    });
    transfer::share_object(treasury);
    transfer::transfer(admin_cap, ctx.sender());
}

/// Any member may deposit SUI into the treasury.
public fun deposit(
    treasury: &mut AllianceTreasury,
    payment: Coin<SUI>,
    ctx: &mut TxContext,
) {
    assert!(!treasury.frozen, ETreasuryFrozen);
    let amount = coin::value(&payment);
    assert!(amount > 0, EZeroAmount);
    treasury.total_deposited = treasury.total_deposited + amount;
    balance::join(&mut treasury.balance, coin::into_balance(payment));
    event::emit(Deposited {
        treasury_id: object::id(treasury),
        depositor: ctx.sender(),
        amount,
        new_balance: balance::value(&treasury.balance),
    });
}

/// Any member can trigger an emergency freeze.
/// Stops all payouts until admin unfreezes.
public fun emergency_freeze(treasury: &mut AllianceTreasury, ctx: &mut TxContext) {
    treasury.frozen = true;
    event::emit(EmergencyFrozen {
        treasury_id: object::id(treasury),
        frozen_by: ctx.sender(),
    });
}

/// Only the AdminCap holder can unfreeze.
public fun unfreeze(
    treasury: &mut AllianceTreasury,
    cap: &AdminCap,
    ctx: &mut TxContext,
) {
    assert!(cap.treasury_id == object::id(treasury), EWrongTreasury);
    treasury.frozen = false;
    event::emit(Unfrozen {
        treasury_id: object::id(treasury),
        unfrozen_by: ctx.sender(),
    });
}

// === Package-internal: called by proposal.move only ===

/// Transfer `amount` SUI to `recipient`. Only callable from within this package.
/// The proposal module calls this after multi-sig threshold is met.
public(package) fun payout(
    treasury: &mut AllianceTreasury,
    amount: u64,
    recipient: address,
    proposal_id: ID,
    ctx: &mut TxContext,
) {
    assert!(!treasury.frozen, ETreasuryFrozen);
    assert!(amount > 0, EZeroAmount);
    assert!(balance::value(&treasury.balance) >= amount, EInsufficientBalance);
    let coin = coin::take(&mut treasury.balance, amount, ctx);
    transfer::public_transfer(coin, recipient);
    treasury.total_paid_out = treasury.total_paid_out + amount;
    event::emit(PaidOut {
        treasury_id: object::id(treasury),
        recipient,
        amount,
        proposal_id,
    });
}

// === View Functions ===

public fun get_balance(treasury: &AllianceTreasury): u64 {
    balance::value(&treasury.balance)
}

public fun is_frozen(treasury: &AllianceTreasury): bool {
    treasury.frozen
}

public fun get_name(treasury: &AllianceTreasury): String {
    treasury.name
}

public fun total_deposited(treasury: &AllianceTreasury): u64 {
    treasury.total_deposited
}

public fun total_paid_out(treasury: &AllianceTreasury): u64 {
    treasury.total_paid_out
}

public fun treasury_id(cap: &AdminCap): ID {
    cap.treasury_id
}
