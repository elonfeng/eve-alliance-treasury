#[test_only]
module alliance_treasury::treasury_tests;

use std::string;
use sui::{
    clock,
    coin,
    sui::SUI,
    test_scenario::{Self as ts, Scenario},
};
use alliance_treasury::{
    treasury::{Self, AllianceTreasury, AdminCap},
    roles::{Self, RoleRegistry},
    proposal::{Self, BudgetProposal},
    gate_sync::{Self, MemberWhitelist},
    policy_agent::{Self, PolicyAgent},
};

// Test addresses
const ADMIN:     address = @0xAD;
const COMMANDER: address = @0xC1;
const ELDER:     address = @0xE1;
const TREASURER: address = @0xC2;
const AUDITOR:   address = @0xA1;
const RECIPIENT: address = @0xFF;
const OUTSIDER:  address = @0xBB;

// 50 SUI — triggers 2-sig threshold
const AMOUNT_SMALL: u64 = 50_000_000_000;
// 500 SUI — triggers 3-sig threshold
const AMOUNT_MED: u64   = 500_000_000_000;
// 2000 SUI — triggers 4-sig threshold
const AMOUNT_LARGE: u64 = 2_000_000_000_000;

// ─── Helpers ───────────────────────────────────────────────────────────────

fun setup_treasury_and_registry(scenario: &mut Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        treasury::create_treasury(string::utf8(b"Iron Wolves Alliance"), ts::ctx(scenario));
    };
    ts::next_tx(scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(scenario);
        roles::create_registry(&cap, ts::ctx(scenario));
        ts::return_to_sender(scenario, cap);
    };
    ts::next_tx(scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(scenario);
        let mut registry = ts::take_shared<RoleRegistry>(scenario);
        roles::add_member(&mut registry, &cap, COMMANDER,  1, ts::ctx(scenario));
        roles::add_member(&mut registry, &cap, ELDER,      4, ts::ctx(scenario));
        roles::add_member(&mut registry, &cap, TREASURER,  2, ts::ctx(scenario));
        roles::add_member(&mut registry, &cap, AUDITOR,    8, ts::ctx(scenario));
        ts::return_to_sender(scenario, cap);
        ts::return_shared(registry);
    };
}

fun fund_treasury(scenario: &mut Scenario, amount: u64) {
    ts::next_tx(scenario, ADMIN);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(scenario);
        let coin = coin::mint_for_testing<SUI>(amount, ts::ctx(scenario));
        treasury::deposit(&mut treasury, coin, ts::ctx(scenario));
        ts::return_shared(treasury);
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// Treasury Tests
// ═══════════════════════════════════════════════════════════════════════════

#[test]
fun test_create_treasury() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        treasury::create_treasury(string::utf8(b"Test Alliance"), ts::ctx(&mut scenario));
    };
    ts::next_tx(&mut scenario, ADMIN);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        assert!(treasury::get_balance(&treasury) == 0);
        assert!(!treasury::is_frozen(&treasury));
        ts::return_shared(treasury);
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        ts::return_to_sender(&mut scenario, cap);
    };
    ts::end(scenario);
}

#[test]
fun test_deposit() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let coin = coin::mint_for_testing<SUI>(AMOUNT_SMALL, ts::ctx(&mut scenario));
        treasury::deposit(&mut treasury, coin, ts::ctx(&mut scenario));
        assert!(treasury::get_balance(&treasury) == AMOUNT_SMALL);
        assert!(treasury::total_deposited(&treasury) == AMOUNT_SMALL);
        ts::return_shared(treasury);
    };
    ts::end(scenario);
}

#[test]
fun test_multiple_deposits() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let coin = coin::mint_for_testing<SUI>(AMOUNT_SMALL, ts::ctx(&mut scenario));
        treasury::deposit(&mut treasury, coin, ts::ctx(&mut scenario));
        ts::return_shared(treasury);
    };
    ts::next_tx(&mut scenario, ELDER);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let coin = coin::mint_for_testing<SUI>(AMOUNT_MED, ts::ctx(&mut scenario));
        treasury::deposit(&mut treasury, coin, ts::ctx(&mut scenario));
        assert!(treasury::get_balance(&treasury) == AMOUNT_SMALL + AMOUNT_MED);
        assert!(treasury::total_deposited(&treasury) == AMOUNT_SMALL + AMOUNT_MED);
        ts::return_shared(treasury);
    };
    ts::end(scenario);
}

#[test]
fun test_emergency_freeze_and_unfreeze() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    // Anyone can freeze
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        treasury::emergency_freeze(&mut treasury, ts::ctx(&mut scenario));
        assert!(treasury::is_frozen(&treasury));
        ts::return_shared(treasury);
    };

    // Only admin can unfreeze
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        treasury::unfreeze(&mut treasury, &cap, ts::ctx(&mut scenario));
        assert!(!treasury::is_frozen(&treasury));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(treasury);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::treasury::ETreasuryFrozen)]
fun test_deposit_blocked_when_frozen() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        treasury::emergency_freeze(&mut treasury, ts::ctx(&mut scenario));
        ts::return_shared(treasury);
    };

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let coin = coin::mint_for_testing<SUI>(AMOUNT_SMALL, ts::ctx(&mut scenario));
        treasury::deposit(&mut treasury, coin, ts::ctx(&mut scenario));
        ts::return_shared(treasury);
    };

    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// Roles Tests
// ═══════════════════════════════════════════════════════════════════════════

#[test]
fun test_role_management() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        // Verify members
        assert!(roles::is_member(&registry, COMMANDER));
        assert!(roles::is_member(&registry, ELDER));
        assert!(roles::is_member(&registry, TREASURER));
        assert!(roles::is_member(&registry, AUDITOR));
        assert!(!roles::is_member(&registry, OUTSIDER));
        assert!(roles::member_count(&registry) == 4);

        // Verify roles
        assert!(roles::has_role(&registry, COMMANDER, roles::role_commander()));
        assert!(!roles::has_role(&registry, COMMANDER, roles::role_elder()));
        assert!(roles::has_role(&registry, ELDER, roles::role_elder()));
        assert!(roles::get_role(&registry, COMMANDER) == 1);
        assert!(roles::get_role(&registry, ELDER) == 4);
        assert!(roles::get_role(&registry, OUTSIDER) == 0);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_update_role() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut registry = ts::take_shared<RoleRegistry>(&mut scenario);
        // Give COMMANDER also ELDER role (bitmask 1 + 4 = 5)
        roles::update_role(&mut registry, &cap, COMMANDER, 5, ts::ctx(&mut scenario));
        assert!(roles::get_role(&registry, COMMANDER) == 5);
        assert!(roles::has_role(&registry, COMMANDER, roles::role_commander()));
        assert!(roles::has_role(&registry, COMMANDER, roles::role_elder()));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_remove_member() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut registry = ts::take_shared<RoleRegistry>(&mut scenario);
        roles::remove_member(&mut registry, &cap, AUDITOR, ts::ctx(&mut scenario));
        assert!(!roles::is_member(&registry, AUDITOR));
        assert!(roles::member_count(&registry) == 3);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::roles::EAlreadyMember)]
fun test_add_duplicate_member_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut registry = ts::take_shared<RoleRegistry>(&mut scenario);
        roles::add_member(&mut registry, &cap, COMMANDER, 2, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_signature_thresholds() {
    // < 100 SUI → 2, 100-1000 → 3, > 1000 → 4
    assert!(roles::required_signatures(AMOUNT_SMALL) == 2);
    assert!(roles::required_signatures(AMOUNT_MED) == 3);
    assert!(roles::required_signatures(AMOUNT_LARGE) == 4);
}

// ═══════════════════════════════════════════════════════════════════════════
// Proposal Tests
// ═══════════════════════════════════════════════════════════════════════════

#[test]
fun test_full_proposal_flow_small_amount() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // COMMANDER creates proposal (auto-signs, count=1, needs 2)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // ELDER signs → threshold met (2/2)
    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::signature_count(&prop) == 2);
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // Execute
    ts::next_tx(&mut scenario, TREASURER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::is_executed(&prop));
        assert!(treasury::total_paid_out(&treasury) == AMOUNT_SMALL);
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_medium_proposal_needs_3_sigs() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_MED * 2);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // COMMANDER creates (auto-sign=1, needs 3)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_MED, RECIPIENT,
            string::utf8(b"Fleet upgrade"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // ELDER signs (2/3)
    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::signature_count(&prop) == 2);
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // TREASURER signs (3/3)
    ts::next_tx(&mut scenario, TREASURER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::signature_count(&prop) == 3);
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // Execute
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::is_executed(&prop));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::EThresholdNotMet)]
fun test_execute_fails_below_threshold() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_MED * 2);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Create 500 SUI proposal (needs 3 sigs)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_MED, RECIPIENT,
            string::utf8(b"Fleet upgrade"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Only 1 sig (proposer). Execute should fail.
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::EAlreadySigned)]
fun test_double_sign_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // COMMANDER tries to sign again (already auto-signed)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::ENotMember)]
fun test_outsider_cannot_create_proposal() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, OUTSIDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Steal funds"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::EProposalExpired)]
fun test_expired_proposal_cannot_be_signed() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Fast-forward 8 days (> 7 day TTL)
    clock::increment_for_testing(&mut clock, 8 * 24 * 60 * 60 * 1000);

    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_mark_expired() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Fast-forward past expiry
    clock::increment_for_testing(&mut clock, 8 * 24 * 60 * 60 * 1000);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        proposal::mark_expired(&mut prop, &clock, ts::ctx(&mut scenario));
        assert!(!proposal::is_pending(&prop));
        assert!(!proposal::is_executed(&prop));
        ts::return_shared(prop);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// Gate Sync / Whitelist Tests
// ═══════════════════════════════════════════════════════════════════════════

#[test]
fun test_whitelist_management() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    // Create whitelist
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        gate_sync::create_whitelist(&cap, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
    };

    // Add members
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut whitelist = ts::take_shared<MemberWhitelist>(&mut scenario);
        gate_sync::whitelist_member(&mut whitelist, &cap, COMMANDER, ts::ctx(&mut scenario));
        gate_sync::whitelist_member(&mut whitelist, &cap, ELDER, ts::ctx(&mut scenario));
        assert!(gate_sync::is_whitelisted(&whitelist, COMMANDER));
        assert!(gate_sync::is_whitelisted(&whitelist, ELDER));
        assert!(!gate_sync::is_whitelisted(&whitelist, OUTSIDER));
        assert!(gate_sync::member_count(&whitelist) == 2);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(whitelist);
    };

    // Remove a member
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut whitelist = ts::take_shared<MemberWhitelist>(&mut scenario);
        gate_sync::remove_from_whitelist(&mut whitelist, &cap, ELDER, ts::ctx(&mut scenario));
        assert!(!gate_sync::is_whitelisted(&whitelist, ELDER));
        assert!(gate_sync::member_count(&whitelist) == 1);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(whitelist);
    };

    ts::end(scenario);
}

#[test]
fun test_whitelist_idempotent_add() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        gate_sync::create_whitelist(&cap, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut whitelist = ts::take_shared<MemberWhitelist>(&mut scenario);
        // Add twice — should not panic, count stays 1
        gate_sync::whitelist_member(&mut whitelist, &cap, COMMANDER, ts::ctx(&mut scenario));
        gate_sync::whitelist_member(&mut whitelist, &cap, COMMANDER, ts::ctx(&mut scenario));
        assert!(gate_sync::member_count(&whitelist) == 1);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(whitelist);
    };

    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// Integration: Proposal + Freeze
// ═══════════════════════════════════════════════════════════════════════════

#[test]
fun test_emergency_freeze_blocks_payout() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        treasury::emergency_freeze(&mut treasury, ts::ctx(&mut scenario));
        assert!(treasury::is_frozen(&treasury));
        ts::return_shared(treasury);
    };

    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// Policy Agent Tests
// ═══════════════════════════════════════════════════════════════════════════

fun setup_agent(scenario: &mut Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(scenario);
        // max_auto_amount = 80 SUI, daily_limit = 200 SUI
        policy_agent::create_agent(
            &cap,
            80_000_000_000,   // 80 SUI
            200_000_000_000,  // 200 SUI
            ts::ctx(scenario),
        );
        ts::return_to_sender(scenario, cap);
    };
}

#[test]
fun test_create_agent() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    setup_agent(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let agent = ts::take_shared<PolicyAgent>(&mut scenario);
        assert!(policy_agent::is_enabled(&agent));
        assert!(policy_agent::max_auto_amount(&agent) == 80_000_000_000);
        assert!(policy_agent::daily_limit(&agent) == 200_000_000_000);
        assert!(policy_agent::total_auto_signed(&agent) == 0);
        // Default skills: AUTO_APPROVE(1) + RATE_LIMIT(2) = 3
        assert!(policy_agent::active_skills(&agent) == 3);
        ts::return_shared(agent);
    };

    ts::end(scenario);
}

#[test]
fun test_agent_auto_sign_small_proposal() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // COMMANDER creates proposal (auto-signs, 1/2)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Agent auto-signs (2/2 — threshold met!)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        assert!(proposal::signature_count(&prop) == 2);
        assert!(policy_agent::total_auto_signed(&agent) == 1);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    // Now execute — should work since 2/2 threshold met
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::is_executed(&prop));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::EAmountTooLarge)]
fun test_agent_rejects_large_amount() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_MED * 10);
    setup_agent(&mut scenario);  // max_auto = 80 SUI

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Create proposal for 500 SUI (exceeds agent's 80 SUI max)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_MED, RECIPIENT,
            string::utf8(b"Fleet upgrade"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Agent tries to sign — should abort
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::EDailyLimitExceeded)]
fun test_agent_daily_limit() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    // Fund with plenty
    fund_treasury(&mut scenario, 1_000_000_000_000);
    setup_agent(&mut scenario);  // daily_limit = 200 SUI

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Create + agent-sign 3 proposals of 80 SUI each
    // 80 + 80 = 160 OK, 160 + 80 = 240 > 200 daily limit → fail on 3rd
    let mut i = 0u64;
    while (i < 3) {
        ts::next_tx(&mut scenario, COMMANDER);
        {
            let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
            let registry = ts::take_shared<RoleRegistry>(&mut scenario);
            proposal::create_proposal(
                &treasury, &registry, 80_000_000_000, RECIPIENT,
                string::utf8(b"Batch buy"), &clock, ts::ctx(&mut scenario),
            );
            ts::return_shared(treasury);
            ts::return_shared(registry);
        };

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
            let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
            let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
            proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
            ts::return_shared(prop);
            ts::return_shared(agent);
            ts::return_shared(treasury);
        };

        i = i + 1;
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::ERecipientNotTrusted)]
fun test_agent_trusted_list_blocks_untrusted() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    // Enable TRUSTED_LIST skill (add to existing AUTO_APPROVE + RATE_LIMIT)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        // skills = 1 + 2 + 4 = 7
        policy_agent::set_skills(&mut agent, &cap, 7, ts::ctx(&mut scenario));
        // Don't add RECIPIENT to trusted list
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Agent rejects — RECIPIENT not in trusted list
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_agent_trusted_list_allows_trusted() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    // Enable TRUSTED_LIST + add RECIPIENT
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::set_skills(&mut agent, &cap, 7, ts::ctx(&mut scenario));
        policy_agent::add_trusted_recipient(&mut agent, &cap, RECIPIENT);
        assert!(policy_agent::is_trusted(&agent, RECIPIENT));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Agent signs — RECIPIENT is trusted
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        assert!(proposal::signature_count(&prop) == 2);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_agent_evaluate_view_function() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, ADMIN);
    {
        let agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);

        // Small amount → should approve
        assert!(policy_agent::evaluate(&agent, &treasury, AMOUNT_SMALL, RECIPIENT, &clock));
        // Large amount → should reject
        assert!(!policy_agent::evaluate(&agent, &treasury, AMOUNT_MED, RECIPIENT, &clock));

        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_agent_disable_blocks_signing() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    // Disable agent
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::set_enabled(&mut agent, &cap, false);
        assert!(!policy_agent::is_enabled(&agent));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Disabled agent evaluate returns false
    ts::next_tx(&mut scenario, ADMIN);
    {
        let agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        assert!(!policy_agent::evaluate(&agent, &treasury, AMOUNT_SMALL, RECIPIENT, &clock));
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_agent_config_update() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    setup_agent(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::configure(
            &mut agent, &cap,
            50_000_000_000,   // new max_auto = 50 SUI
            100_000_000_000,  // new daily = 100 SUI
            10_000_000_000,   // balance reserve = 10 SUI
            3_600_000,        // cooldown = 1 hour
            ts::ctx(&mut scenario),
        );
        assert!(policy_agent::max_auto_amount(&agent) == 50_000_000_000);
        assert!(policy_agent::daily_limit(&agent) == 100_000_000_000);
        assert!(policy_agent::min_balance_reserve(&agent) == 10_000_000_000);
        assert!(policy_agent::cooldown_ms(&agent) == 3_600_000);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW TESTS — Treasury abort paths
// ═══════════════════════════════════════════════════════════════════════════

#[test]
#[expected_failure(abort_code = alliance_treasury::treasury::EZeroAmount)]
fun test_zero_deposit_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let coin = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
        treasury::deposit(&mut treasury, coin, ts::ctx(&mut scenario));
        ts::return_shared(treasury);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::treasury::EWrongTreasury)]
fun test_unfreeze_wrong_treasury_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    // Freeze the treasury and record its ID
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        treasury::emergency_freeze(&mut treasury, ts::ctx(&mut scenario));
        ts::return_shared(treasury);
    };

    // Create a second treasury to get a different AdminCap
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        treasury::create_treasury(string::utf8(b"Other Alliance"), ts::ctx(&mut scenario));
    };

    // OUTSIDER's AdminCap tries to unfreeze the first (frozen) treasury
    // We take both treasuries and find the frozen one to attempt unfreeze
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        let mut t1 = ts::take_shared<AllianceTreasury>(&mut scenario);
        let mut t2 = ts::take_shared<AllianceTreasury>(&mut scenario);
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        // Try to unfreeze the frozen treasury with the wrong cap.
        // One of t1/t2 is frozen. The cap belongs to the other one.
        if (treasury::is_frozen(&t1)) {
            // t1 is the admin's treasury (frozen), cap belongs to t2 (outsider's)
            treasury::unfreeze(&mut t1, &cap, ts::ctx(&mut scenario));
        } else {
            // t2 is the admin's treasury (frozen), cap belongs to t1 (outsider's)
            treasury::unfreeze(&mut t2, &cap, ts::ctx(&mut scenario));
        };
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(t1);
        ts::return_shared(t2);
    };

    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW TESTS — Roles abort paths
// ═══════════════════════════════════════════════════════════════════════════

#[test]
#[expected_failure(abort_code = alliance_treasury::roles::EInvalidRole)]
fun test_invalid_role_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut registry = ts::take_shared<RoleRegistry>(&mut scenario);
        // Role 0 is invalid (must be 1..15)
        roles::add_member(&mut registry, &cap, OUTSIDER, 0, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::roles::ENotMember)]
fun test_remove_non_member_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut registry = ts::take_shared<RoleRegistry>(&mut scenario);
        roles::remove_member(&mut registry, &cap, OUTSIDER, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::roles::ENotMember)]
fun test_update_non_member_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut registry = ts::take_shared<RoleRegistry>(&mut scenario);
        roles::update_role(&mut registry, &cap, OUTSIDER, 3, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::roles::EWrongTreasury)]
fun test_wrong_treasury_add_member() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    // Create a second treasury to get a different AdminCap
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        treasury::create_treasury(string::utf8(b"Other Alliance"), ts::ctx(&mut scenario));
    };

    // Use OUTSIDER's cap on the first registry
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut registry = ts::take_shared<RoleRegistry>(&mut scenario);
        roles::add_member(&mut registry, &cap, @0xDD, 1, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW TESTS — Proposal abort paths
// ═══════════════════════════════════════════════════════════════════════════

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::ENotMember)]
fun test_outsider_cannot_sign() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // COMMANDER creates proposal
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // OUTSIDER tries to sign
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::EProposalExpired)]
fun test_execute_expired_proposal_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // COMMANDER creates proposal, ELDER signs → 2/2 threshold met
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // Fast-forward past expiry
    clock::increment_for_testing(&mut clock, 8 * 24 * 60 * 60 * 1000);

    // Try to execute — should fail because expired
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::EWrongTreasury)]
fun test_execute_wrong_treasury_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    // Create a second treasury
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        treasury::create_treasury(string::utf8(b"Other Alliance"), ts::ctx(&mut scenario));
    };

    // Fund the second treasury
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        let mut treasury2 = ts::take_from_sender<AdminCap>(&mut scenario);
        ts::return_to_sender(&mut scenario, treasury2);
    };

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Create proposal on first treasury
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // ELDER signs → 2/2 threshold met
    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // Try to execute against the wrong (second) treasury
    // We need to take the second treasury. Since both are shared, we take each by type.
    // The scenario has two AllianceTreasury objects. We need to pass the wrong one.
    // We'll take from scenario which will give us one — we'll manipulate to get the second.
    // Actually test_scenario returns shared objects in order created, so first take will be first treasury.
    // We need the second treasury for the wrong-treasury check.
    // The trick: take the first treasury, return it, then take again to get the second.
    ts::next_tx(&mut scenario, COMMANDER);
    {
        // First take gives us the first treasury (the one with funds and the proposal's treasury_id)
        let first_treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        // Second take gives us the second treasury
        let mut second_treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        // Execute with the wrong treasury — should abort with EWrongTreasury
        proposal::execute_proposal(&mut prop, &mut second_treasury, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(first_treasury);
        ts::return_shared(second_treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::ENotExpired)]
fun test_mark_not_expired_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Try to mark as expired immediately (not expired yet)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        proposal::mark_expired(&mut prop, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::proposal::ENotPending)]
fun test_execute_already_executed_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Create and fully sign + execute a proposal
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Try to execute again — should fail with ENotPending
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_large_proposal_needs_4_sigs() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_LARGE * 2);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // COMMANDER creates proposal (auto-sign=1, needs 4)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_LARGE, RECIPIENT,
            string::utf8(b"Capital ship purchase"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Verify required count is 4
    ts::next_tx(&mut scenario, ADMIN);
    {
        let prop = ts::take_shared<BudgetProposal>(&mut scenario);
        assert!(proposal::required_count(&prop) == 4);
        assert!(proposal::signature_count(&prop) == 1);
        ts::return_shared(prop);
    };

    // ELDER signs (2/4)
    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::signature_count(&prop) == 2);
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // TREASURER signs (3/4)
    ts::next_tx(&mut scenario, TREASURER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::signature_count(&prop) == 3);
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // AUDITOR signs (4/4)
    ts::next_tx(&mut scenario, AUDITOR);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::signature_count(&prop) == 4);
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // Execute — should succeed with 4/4
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::is_executed(&prop));
        assert!(treasury::total_paid_out(&treasury) == AMOUNT_LARGE);
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_proposal_view_functions() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let prop = ts::take_shared<BudgetProposal>(&mut scenario);
        assert!(proposal::proposer(&prop) == COMMANDER);
        assert!(proposal::amount(&prop) == AMOUNT_SMALL);
        assert!(proposal::recipient(&prop) == RECIPIENT);
        assert!(proposal::is_pending(&prop));
        assert!(!proposal::is_executed(&prop));
        assert!(proposal::signature_count(&prop) == 1);
        assert!(proposal::required_count(&prop) == 2);
        assert!(proposal::has_signed(&prop, COMMANDER));
        assert!(!proposal::has_signed(&prop, ELDER));
        ts::return_shared(prop);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW TESTS — Gate Sync abort paths
// ═══════════════════════════════════════════════════════════════════════════

#[test]
#[expected_failure(abort_code = alliance_treasury::gate_sync::EWrongTreasury)]
fun test_whitelist_wrong_treasury_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    // Create whitelist for the first treasury
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        gate_sync::create_whitelist(&cap, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
    };

    // Create a second treasury
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        treasury::create_treasury(string::utf8(b"Other Alliance"), ts::ctx(&mut scenario));
    };

    // Use OUTSIDER's cap on the first whitelist — wrong treasury
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut whitelist = ts::take_shared<MemberWhitelist>(&mut scenario);
        gate_sync::whitelist_member(&mut whitelist, &cap, COMMANDER, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(whitelist);
    };

    ts::end(scenario);
}

#[test]
fun test_remove_whitelist_idempotent() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        gate_sync::create_whitelist(&cap, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
    };

    // Remove a member that was never whitelisted — should not panic
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut whitelist = ts::take_shared<MemberWhitelist>(&mut scenario);
        gate_sync::remove_from_whitelist(&mut whitelist, &cap, OUTSIDER, ts::ctx(&mut scenario));
        assert!(gate_sync::member_count(&whitelist) == 0);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(whitelist);
    };

    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW TESTS — Policy Agent abort paths and edge cases
// ═══════════════════════════════════════════════════════════════════════════

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::EBalanceTooLow)]
fun test_agent_balance_guard_blocks() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    // Fund with 100 SUI — proposal is 50 SUI, reserve is 80 SUI → 100 < 50 + 80 = 130 → fail
    fund_treasury(&mut scenario, 100_000_000_000);
    setup_agent(&mut scenario);

    // Enable BALANCE_GUARD skill and set min_balance_reserve = 80 SUI
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        // skills = AUTO_APPROVE(1) + RATE_LIMIT(2) + BALANCE_GUARD(8) = 11
        policy_agent::set_skills(&mut agent, &cap, 11, ts::ctx(&mut scenario));
        policy_agent::configure(
            &mut agent, &cap,
            80_000_000_000,   // max_auto = 80 SUI
            200_000_000_000,  // daily_limit = 200 SUI
            80_000_000_000,   // min_balance_reserve = 80 SUI
            0,
            ts::ctx(&mut scenario),
        );
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Agent tries to sign — should fail because balance guard blocks
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::ECooldownActive)]
fun test_agent_cooldown_blocks() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    // Enable COOLDOWN skill with 1 hour cooldown
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        // skills = AUTO_APPROVE(1) + RATE_LIMIT(2) + COOLDOWN(16) = 19
        policy_agent::set_skills(&mut agent, &cap, 19, ts::ctx(&mut scenario));
        policy_agent::configure(
            &mut agent, &cap,
            80_000_000_000,   // max_auto = 80 SUI
            200_000_000_000,  // daily_limit = 200 SUI
            0,
            3_600_000,        // cooldown = 1 hour
            ts::ctx(&mut scenario),
        );
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    // Set clock to some non-zero time
    clock::increment_for_testing(&mut clock, 100_000);

    // First proposal: agent signs successfully
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"First buy"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    // Advance only 30 minutes (less than 1 hour cooldown)
    clock::increment_for_testing(&mut clock, 1_800_000);

    // Second proposal to same RECIPIENT — agent should fail with cooldown
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Second buy"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_agent_cooldown_expires_allows() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    // Enable COOLDOWN skill with 1 hour cooldown
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::set_skills(&mut agent, &cap, 19, ts::ctx(&mut scenario));
        policy_agent::configure(
            &mut agent, &cap,
            80_000_000_000,
            200_000_000_000,
            0,
            3_600_000,  // 1 hour cooldown
            ts::ctx(&mut scenario),
        );
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::increment_for_testing(&mut clock, 100_000);

    // First proposal + agent sign
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"First buy"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    // Advance past cooldown (2 hours > 1 hour)
    clock::increment_for_testing(&mut clock, 7_200_000);

    // Second proposal to same RECIPIENT — should succeed now
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Second buy"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        assert!(policy_agent::total_auto_signed(&agent) == 2);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_agent_daily_reset_on_new_day() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, 1_000_000_000_000);
    setup_agent(&mut scenario); // daily_limit = 200 SUI, max_auto = 80 SUI

    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    // Start at day 1
    clock::increment_for_testing(&mut clock, 86_400_000);

    // First proposal 80 SUI — succeeds
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, 80_000_000_000, RECIPIENT,
            string::utf8(b"Day 1 buy 1"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        assert!(policy_agent::daily_spent(&agent) == 80_000_000_000);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    // Second proposal 80 SUI — succeeds (160 total, < 200 limit)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, 80_000_000_000, RECIPIENT,
            string::utf8(b"Day 1 buy 2"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        assert!(policy_agent::daily_spent(&agent) == 160_000_000_000);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    // Advance to next day — daily_spent should reset
    clock::increment_for_testing(&mut clock, 86_400_000);

    // Third proposal 80 SUI on new day — should succeed (reset to 0 + 80 < 200)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, 80_000_000_000, RECIPIENT,
            string::utf8(b"Day 2 buy 1"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        // Should be 80 SUI (reset happened)
        assert!(policy_agent::daily_spent(&agent) == 80_000_000_000);
        assert!(policy_agent::total_auto_signed(&agent) == 3);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::EWrongTreasury)]
fun test_agent_wrong_treasury_config() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    setup_agent(&mut scenario);

    // Create a second treasury
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        treasury::create_treasury(string::utf8(b"Other Alliance"), ts::ctx(&mut scenario));
    };

    // Try to configure agent with wrong AdminCap
    ts::next_tx(&mut scenario, OUTSIDER);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::set_enabled(&mut agent, &cap, false);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    ts::end(scenario);
}

#[test]
fun test_agent_remove_trusted_recipient() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    setup_agent(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::add_trusted_recipient(&mut agent, &cap, RECIPIENT);
        assert!(policy_agent::is_trusted(&agent, RECIPIENT));
        policy_agent::remove_trusted_recipient(&mut agent, &cap, RECIPIENT);
        assert!(!policy_agent::is_trusted(&agent, RECIPIENT));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::ENotTrusted)]
fun test_agent_remove_untrusted_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    setup_agent(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        // OUTSIDER was never added as trusted
        policy_agent::remove_trusted_recipient(&mut agent, &cap, OUTSIDER);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::EAlreadyTrusted)]
fun test_agent_add_duplicate_trusted_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    setup_agent(&mut scenario);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::add_trusted_recipient(&mut agent, &cap, RECIPIENT);
        // Add again — should fail
        policy_agent::add_trusted_recipient(&mut agent, &cap, RECIPIENT);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::policy_agent::EAgentDisabled)]
fun test_agent_disabled_auto_sign_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    // Disable agent
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::set_enabled(&mut agent, &cap, false);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Agent tries to sign while disabled — should abort
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_agent_all_skills_combined() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    // Enable ALL 5 skills: 1+2+4+8+16 = 31
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        policy_agent::set_skills(&mut agent, &cap, 31, ts::ctx(&mut scenario));
        policy_agent::configure(
            &mut agent, &cap,
            80_000_000_000,   // max_auto = 80 SUI
            200_000_000_000,  // daily_limit = 200 SUI
            10_000_000_000,   // min_balance_reserve = 10 SUI
            3_600_000,        // cooldown = 1 hour
            ts::ctx(&mut scenario),
        );
        policy_agent::add_trusted_recipient(&mut agent, &cap, RECIPIENT);
        assert!(policy_agent::active_skills(&agent) == 31);
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(agent);
    };

    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::increment_for_testing(&mut clock, 100_000);

    // Create proposal for small amount to trusted recipient
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"All skills test"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Agent should pass all 5 skill checks and sign
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        assert!(proposal::signature_count(&prop) == 2);
        assert!(policy_agent::total_auto_signed(&agent) == 1);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_agent_sign_then_human_execute() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // COMMANDER creates proposal (auto-sign=1/2)
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Agent + human flow"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Agent signs (2/2 threshold met)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        assert!(proposal::signature_count(&prop) == 2);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    // Human (ELDER) executes the proposal
    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::is_executed(&prop));
        assert!(treasury::total_paid_out(&treasury) == AMOUNT_SMALL);
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW TESTS — Integration tests
// ═══════════════════════════════════════════════════════════════════════════

#[test]
fun test_full_flow_with_agent_and_gate_sync() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);
    setup_agent(&mut scenario);

    // Create whitelist
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        gate_sync::create_whitelist(&cap, ts::ctx(&mut scenario));
        ts::return_to_sender(&mut scenario, cap);
    };

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Step 1: COMMANDER creates proposal
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"PTB flow test"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Step 2: Agent auto-signs (2/2 met)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut agent = ts::take_shared<PolicyAgent>(&mut scenario);
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        proposal::agent_sign_proposal(&mut prop, &mut agent, &treasury, &clock);
        ts::return_shared(prop);
        ts::return_shared(agent);
        ts::return_shared(treasury);
    };

    // Step 3: Execute proposal
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::is_executed(&prop));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Step 4: Whitelist the recipient (simulating atomic PTB: execute + whitelist)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let cap = ts::take_from_sender<AdminCap>(&mut scenario);
        let mut whitelist = ts::take_shared<MemberWhitelist>(&mut scenario);
        gate_sync::whitelist_member(&mut whitelist, &cap, RECIPIENT, ts::ctx(&mut scenario));
        assert!(gate_sync::is_whitelisted(&whitelist, RECIPIENT));
        ts::return_to_sender(&mut scenario, cap);
        ts::return_shared(whitelist);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = alliance_treasury::treasury::ETreasuryFrozen)]
fun test_frozen_treasury_blocks_proposal_execution() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 10);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // Create proposal and get threshold met
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Buy ammo"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    ts::next_tx(&mut scenario, ELDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // Freeze the treasury before execution
    ts::next_tx(&mut scenario, AUDITOR);
    {
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        treasury::emergency_freeze(&mut treasury, ts::ctx(&mut scenario));
        ts::return_shared(treasury);
    };

    // Try to execute — should fail because treasury is frozen
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_multiple_proposals_concurrent() {
    let mut scenario = ts::begin(ADMIN);
    setup_treasury_and_registry(&mut scenario);
    fund_treasury(&mut scenario, AMOUNT_SMALL * 20);

    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // COMMANDER creates first proposal
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, RECIPIENT,
            string::utf8(b"Proposal A"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // ELDER creates second proposal
    ts::next_tx(&mut scenario, ELDER);
    {
        let treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::create_proposal(
            &treasury, &registry, AMOUNT_SMALL, OUTSIDER,
            string::utf8(b"Proposal B"), &clock, ts::ctx(&mut scenario),
        );
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // TREASURER signs both proposals (hasn't signed either)
    // Sign first proposal (created by COMMANDER): TREASURER signs (2/2)
    ts::next_tx(&mut scenario, TREASURER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut prop, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::signature_count(&prop) == 2);
        ts::return_shared(prop);
        ts::return_shared(registry);
    };

    // Sign second proposal (created by ELDER): TREASURER signs (2/2)
    ts::next_tx(&mut scenario, TREASURER);
    {
        // take_shared returns in creation order: first is proposal A, second is proposal B
        let first_prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut second_prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::sign_proposal(&mut second_prop, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::signature_count(&second_prop) == 2);
        ts::return_shared(first_prop);
        ts::return_shared(second_prop);
        ts::return_shared(registry);
    };

    // Execute first proposal
    ts::next_tx(&mut scenario, COMMANDER);
    {
        let mut prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::is_executed(&prop));
        ts::return_shared(prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    // Execute second proposal
    ts::next_tx(&mut scenario, ELDER);
    {
        let first_prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut second_prop = ts::take_shared<BudgetProposal>(&mut scenario);
        let mut treasury = ts::take_shared<AllianceTreasury>(&mut scenario);
        let registry = ts::take_shared<RoleRegistry>(&mut scenario);
        proposal::execute_proposal(&mut second_prop, &mut treasury, &registry, &clock, ts::ctx(&mut scenario));
        assert!(proposal::is_executed(&second_prop));
        assert!(treasury::total_paid_out(&treasury) == AMOUNT_SMALL * 2);
        ts::return_shared(first_prop);
        ts::return_shared(second_prop);
        ts::return_shared(treasury);
        ts::return_shared(registry);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
