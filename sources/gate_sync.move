/// Gate Sync — alliance-controlled Smart Gate extension.
///
/// Architectural highlight: governance decisions (treasury approvals) can be
/// atomically combined with gate access changes in a single PTB transaction.
///
/// Example PTB:
///   Step 1: proposal::execute_proposal(...)      → transfers SUI to recipient
///   Step 2: gate_sync::whitelist_member(...)      → adds new member to gate whitelist
///   Both succeed or both fail — atomic, no partial state.
///
/// Gate access: only whitelisted alliance members can obtain a JumpPermit
/// from any gate that has registered AllianceAuth as its extension.
module alliance_treasury::gate_sync;

use sui::{
    clock::{Self, Clock},
    event,
    table::{Self, Table},
};
use world::{
    access::OwnerCap,
    character::Character,
    gate::{Self, Gate},
};
use alliance_treasury::treasury::AdminCap;

// === Witness ===
// Typed witness registered on the Gate. Gate will require AllianceAuth
// for all jump operations once extension is authorized.
public struct AllianceAuth has drop {}

// === Constants ===
const PERMIT_TTL_MS: u64 = 24 * 60 * 60 * 1000; // 24 hours

// === Errors ===
const ENotWhitelisted:   u64 = 0;
const EWrongTreasury:    u64 = 1;

// === Structs ===

/// Shared object — tracks which wallet addresses are alliance members
/// for gate access purposes. One per treasury/alliance.
public struct MemberWhitelist has key {
    id: UID,
    treasury_id: ID,
    members: Table<address, bool>,
    member_count: u64,
}

// === Events ===

public struct WhitelistCreated has copy, drop {
    whitelist_id: ID,
    treasury_id: ID,
    creator: address,
}

public struct MemberWhitelisted has copy, drop {
    whitelist_id: ID,
    member: address,
    added_by: address,
}

public struct MemberRemovedFromWhitelist has copy, drop {
    whitelist_id: ID,
    member: address,
    removed_by: address,
}

public struct PermitIssued has copy, drop {
    member: address,
    source_gate_id: ID,
    dest_gate_id: ID,
    expires_at: u64,
}

// === Public Entry Functions ===

/// Create a MemberWhitelist for this alliance's treasury. Admin only.
public fun create_whitelist(cap: &AdminCap, ctx: &mut TxContext) {
    let whitelist = MemberWhitelist {
        id: object::new(ctx),
        treasury_id: alliance_treasury::treasury::treasury_id(cap),
        members: table::new(ctx),
        member_count: 0,
    };
    event::emit(WhitelistCreated {
        whitelist_id: object::id(&whitelist),
        treasury_id: whitelist.treasury_id,
        creator: ctx.sender(),
    });
    transfer::share_object(whitelist);
}

/// Add a member to the gate whitelist. Admin only.
/// Called in PTB alongside execute_proposal for atomic governance + access update.
public fun whitelist_member(
    whitelist: &mut MemberWhitelist,
    cap: &AdminCap,
    member: address,
    ctx: &mut TxContext,
) {
    assert!(alliance_treasury::treasury::treasury_id(cap) == whitelist.treasury_id, EWrongTreasury);
    if (!table::contains(&whitelist.members, member)) {
        table::add(&mut whitelist.members, member, true);
        whitelist.member_count = whitelist.member_count + 1;
        event::emit(MemberWhitelisted {
            whitelist_id: object::id(whitelist),
            member,
            added_by: ctx.sender(),
        });
    }
}

/// Remove a member from the gate whitelist. Admin only.
public fun remove_from_whitelist(
    whitelist: &mut MemberWhitelist,
    cap: &AdminCap,
    member: address,
    ctx: &mut TxContext,
) {
    assert!(alliance_treasury::treasury::treasury_id(cap) == whitelist.treasury_id, EWrongTreasury);
    if (table::contains(&whitelist.members, member)) {
        table::remove(&mut whitelist.members, member);
        whitelist.member_count = whitelist.member_count - 1;
        event::emit(MemberRemovedFromWhitelist {
            whitelist_id: object::id(whitelist),
            member,
            removed_by: ctx.sender(),
        });
    }
}

/// Register AllianceAuth as the extension on a gate.
/// Called once by the gate owner. After this, only AllianceAuth permits work.
public fun authorize_on_gate(
    gate: &mut Gate,
    owner_cap: &OwnerCap<Gate>,
    _ctx: &mut TxContext,
) {
    gate::authorize_extension<AllianceAuth>(gate, owner_cap);
}

/// Issue a JumpPermit to a whitelisted alliance member.
/// The character's address must be in the MemberWhitelist.
/// Permit is valid for 24 hours.
public fun issue_member_permit(
    whitelist: &MemberWhitelist,
    source_gate: &Gate,
    dest_gate: &Gate,
    character: &Character,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let char_addr = character.character_address();
    assert!(table::contains(&whitelist.members, char_addr), ENotWhitelisted);

    let expires_at = clock::timestamp_ms(clock) + PERMIT_TTL_MS;

    gate::issue_jump_permit<AllianceAuth>(
        source_gate,
        dest_gate,
        character,
        AllianceAuth {},
        expires_at,
        ctx,
    );

    event::emit(PermitIssued {
        member: char_addr,
        source_gate_id: object::id(source_gate),
        dest_gate_id: object::id(dest_gate),
        expires_at,
    });
}

// === View Functions ===

public fun is_whitelisted(whitelist: &MemberWhitelist, addr: address): bool {
    table::contains(&whitelist.members, addr)
}

public fun member_count(whitelist: &MemberWhitelist): u64 {
    whitelist.member_count
}
