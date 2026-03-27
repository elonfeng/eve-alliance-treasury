/// Alliance Roles — member registry with role-based permissions.
///
/// Roles (bitmask, combinable):
///   COMMANDER  = 1  — can submit military spending proposals
///   TREASURER  = 2  — can submit operational expense proposals
///   ELDER      = 4  — required for large-amount approvals
///   AUDITOR    = 8  — read-only, can trigger emergency freeze
///
/// Signature thresholds by amount:
///   < 100 SUI   → 2 signatures required
///   100-1000 SUI → 3 signatures required
///   > 1000 SUI  → 4 signatures required
module alliance_treasury::roles;

use sui::{
    event,
    table::{Self, Table},
};
use alliance_treasury::treasury::AdminCap;

// === Role Constants (bitmask) ===
const ROLE_COMMANDER: u8 = 1;
const ROLE_TREASURER: u8 = 2;
const ROLE_ELDER:     u8 = 4;
const ROLE_AUDITOR:   u8 = 8;

// === Signature Thresholds ===
const SMALL_THRESHOLD:  u64 = 100_000_000_000;    // 100 SUI in MIST
const LARGE_THRESHOLD:  u64 = 1_000_000_000_000;  // 1000 SUI in MIST
const SIGS_SMALL:  u64 = 2;
const SIGS_MEDIUM: u64 = 3;
const SIGS_LARGE:  u64 = 4;

// === Errors ===
const EAlreadyMember:  u64 = 0;
const ENotMember:      u64 = 1;
const EInvalidRole:    u64 = 2;
const EWrongTreasury:  u64 = 3;

// === Structs ===

/// Shared object — stores all member → role mappings for one treasury.
public struct RoleRegistry has key {
    id: UID,
    treasury_id: ID,
    members: Table<address, u8>,
    member_count: u64,
}

// === Events ===

public struct RegistryCreated has copy, drop {
    registry_id: ID,
    treasury_id: ID,
    creator: address,
}

public struct MemberAdded has copy, drop {
    registry_id: ID,
    member: address,
    role: u8,
    added_by: address,
}

public struct MemberRemoved has copy, drop {
    registry_id: ID,
    member: address,
    removed_by: address,
}

public struct RoleUpdated has copy, drop {
    registry_id: ID,
    member: address,
    new_role: u8,
}

// === Public Entry Functions ===

/// Create a RoleRegistry linked to a treasury. Admin only.
public fun create_registry(cap: &AdminCap, ctx: &mut TxContext) {
    let registry = RoleRegistry {
        id: object::new(ctx),
        treasury_id: alliance_treasury::treasury::treasury_id(cap),
        members: table::new(ctx),
        member_count: 0,
    };
    event::emit(RegistryCreated {
        registry_id: object::id(&registry),
        treasury_id: registry.treasury_id,
        creator: ctx.sender(),
    });
    sui::transfer::share_object(registry);
}

/// Add a member with a role. Admin only.
/// Role is a bitmask: COMMANDER=1, TREASURER=2, ELDER=4, AUDITOR=8
/// Example: COMMANDER + ELDER = 5
public fun add_member(
    registry: &mut RoleRegistry,
    cap: &AdminCap,
    member: address,
    role: u8,
    ctx: &mut TxContext,
) {
    assert!(alliance_treasury::treasury::treasury_id(cap) == registry.treasury_id, EWrongTreasury);
    assert!(!table::contains(&registry.members, member), EAlreadyMember);
    assert!(role >= 1 && role <= 15, EInvalidRole);
    table::add(&mut registry.members, member, role);
    registry.member_count = registry.member_count + 1;
    event::emit(MemberAdded {
        registry_id: object::id(registry),
        member,
        role,
        added_by: ctx.sender(),
    });
}

/// Remove a member from the registry. Admin only.
public fun remove_member(
    registry: &mut RoleRegistry,
    cap: &AdminCap,
    member: address,
    ctx: &mut TxContext,
) {
    assert!(alliance_treasury::treasury::treasury_id(cap) == registry.treasury_id, EWrongTreasury);
    assert!(table::contains(&registry.members, member), ENotMember);
    table::remove(&mut registry.members, member);
    registry.member_count = registry.member_count - 1;
    event::emit(MemberRemoved {
        registry_id: object::id(registry),
        member,
        removed_by: ctx.sender(),
    });
}

/// Update a member's role bitmask. Admin only.
public fun update_role(
    registry: &mut RoleRegistry,
    cap: &AdminCap,
    member: address,
    new_role: u8,
    _ctx: &mut TxContext,
) {
    assert!(alliance_treasury::treasury::treasury_id(cap) == registry.treasury_id, EWrongTreasury);
    assert!(table::contains(&registry.members, member), ENotMember);
    assert!(new_role >= 1 && new_role <= 15, EInvalidRole);
    *table::borrow_mut(&mut registry.members, member) = new_role;
    event::emit(RoleUpdated {
        registry_id: object::id(registry),
        member,
        new_role,
    });
}

// === View Functions ===

public fun is_member(registry: &RoleRegistry, addr: address): bool {
    table::contains(&registry.members, addr)
}

public fun has_role(registry: &RoleRegistry, addr: address, role: u8): bool {
    if (!table::contains(&registry.members, addr)) return false;
    let member_role = *table::borrow(&registry.members, addr);
    (member_role & role) != 0
}

public fun get_role(registry: &RoleRegistry, addr: address): u8 {
    if (!table::contains(&registry.members, addr)) return 0;
    *table::borrow(&registry.members, addr)
}

public fun member_count(registry: &RoleRegistry): u64 {
    registry.member_count
}

/// Returns number of signatures required based on proposal amount.
public fun required_signatures(amount: u64): u64 {
    if (amount >= LARGE_THRESHOLD) SIGS_LARGE
    else if (amount >= SMALL_THRESHOLD) SIGS_MEDIUM
    else SIGS_SMALL
}

public fun role_commander(): u8 { ROLE_COMMANDER }
public fun role_treasurer(): u8 { ROLE_TREASURER }
public fun role_elder(): u8 { ROLE_ELDER }
public fun role_auditor(): u8 { ROLE_AUDITOR }
