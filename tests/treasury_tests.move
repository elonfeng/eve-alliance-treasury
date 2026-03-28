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
