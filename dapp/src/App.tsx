import { useState, useEffect, useCallback } from "react";
import { useConnection } from "@evefrontier/dapp-kit";
import { useCurrentAccount, useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

import { HudBar } from "./components/HudBar";
import { SetupTab } from "./components/SetupTab";
import { GovernanceTab } from "./components/GovernanceTab";
import { AgentTab } from "./components/AgentTab";
import { IntelTab } from "./components/IntelTab";

const PACKAGE_ID = import.meta.env.VITE_PACKAGE_ID || "0x0";
const BACKEND_URL = import.meta.env.VITE_BACKEND_URL || "http://localhost:3001";

function target(module: string, fn: string): `${string}::${string}::${string}` {
  return `${PACKAGE_ID}::${module}::${fn}`;
}

type Tab = "setup" | "governance" | "agent" | "intel";

const TABS: { id: Tab; label: string }[] = [
  { id: "setup", label: "Setup" },
  { id: "governance", label: "Governance" },
  { id: "agent", label: "Agent" },
  { id: "intel", label: "Intel" },
];

function App() {
  const { handleConnect, handleDisconnect } = useConnection();
  const { signAndExecuteTransaction } = useDAppKit();
  const account = useCurrentAccount();

  const [activeTab, setActiveTab] = useState<Tab>("setup");
  const [status, setStatus] = useState("");
  const [lastTxDigest, setLastTxDigest] = useState("");

  // Object IDs
  const [treasuryId, setTreasuryId] = useState("");
  const [adminCapId, setAdminCapId] = useState("");
  const [registryId, setRegistryId] = useState("");
  const [proposalId, setProposalId] = useState("");

  // Form state
  const [allianceName, setAllianceName] = useState("Iron Wolves Alliance");
  const [memberAddr, setMemberAddr] = useState("");
  const [memberRole, setMemberRole] = useState("1");
  const [depositAmount, setDepositAmount] = useState("0.1");
  const [proposalAmount, setProposalAmount] = useState("0.05");
  const [proposalRecipient, setProposalRecipient] = useState("");
  const [proposalPurpose, setProposalPurpose] = useState("Buy fleet supplies");

  // Agent state
  const [agentMaxAuto, setAgentMaxAuto] = useState("100");
  const [agentDailyLimit, setAgentDailyLimit] = useState("500");
  const [agentProposalId, setAgentProposalId] = useState("");
  const [agentSkills, setAgentSkills] = useState<Record<string, boolean>>({
    auto_sign: true,
    rate_limit: true,
    trusted_list: false,
    balance_guard: false,
    cooldown: false,
  });

  // Backend state
  interface BackendProposal { id: string; purpose: string; amount: string; status: string; created_at: string; }
  interface AuditEntry { proposal_id: string; purpose: string; proposer: string; recipient: string; amount: string; executor: string; executed_at: string; }
  interface AgentStats { proposals: { total: number; pending: number; executed: number; expired: number }; payouts: { count: number; total_amount_mist: string }; signatures: number; killmails: number; jumps: number; }
  interface KillMail { killer_id: string; victim_id: string; loss_type: string; kill_timestamp: string; }

  const [backendOnline, setBackendOnline] = useState<boolean | null>(null);
  const [proposals, setProposals] = useState<BackendProposal[]>([]);
  const [auditLog, setAuditLog] = useState<AuditEntry[]>([]);
  const [agentStats, setAgentStats] = useState<AgentStats | null>(null);
  const [killMails, setKillMails] = useState<KillMail[]>([]);
  const [backendLoading, setBackendLoading] = useState(false);

  // Auto-dismiss status
  useEffect(() => {
    if (status) {
      const timer = setTimeout(() => setStatus(""), 5000);
      return () => clearTimeout(timer);
    }
  }, [status]);

  // ── Backend fetch ──────────────────────────────────────────────────

  const safeFetch = useCallback(async (url: string) => {
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.json();
    } catch { return null; }
  }, []);

  const fetchBackendData = useCallback(async () => {
    setBackendLoading(true);
    const [propData, auditData, statsData, kmData] = await Promise.all([
      safeFetch(`${BACKEND_URL}/api/proposals?limit=5`),
      safeFetch(`${BACKEND_URL}/api/audit?limit=5`),
      safeFetch(`${BACKEND_URL}/api/agent/stats`),
      safeFetch(`${BACKEND_URL}/api/killmails?limit=10`),
    ]);
    const online = propData !== null || auditData !== null || statsData !== null;
    setBackendOnline(online);
    if (propData) setProposals(propData.data || propData);
    if (auditData) setAuditLog(auditData.data || auditData);
    if (statsData) setAgentStats(statsData);
    if (kmData) setKillMails(kmData.data || kmData);
    setBackendLoading(false);
  }, [safeFetch]);

  useEffect(() => { fetchBackendData(); }, [fetchBackendData]);

  // ── Transaction helper ─────────────────────────────────────────────

  const exec = async (tx: Transaction, label: string) => {
    setStatus(`${label}...`);
    try {
      if (!account) throw new Error("Wallet not connected");
      // Serialize to JSON string first, then wrap — avoids version mismatch with EVE Vault
      const jsonStr = await tx.toJSON();
      const result: any = await signAndExecuteTransaction({
        transaction: jsonStr as any,
      });
      setLastTxDigest(result?.digest || "");
      setStatus(`${label} succeeded`);
      return result;
    } catch (e: any) {
      const msg = e?.message || String(e);
      setStatus(`${label} failed: ${msg.slice(0, 120)}`);
      console.error(`${label} error:`, e);
      return null;
    }
  };

  // ── Actions ────────────────────────────────────────────────────────

  const createTreasury = async () => {
    const tx = new Transaction();
    tx.moveCall({ target: target("treasury", "create_treasury"), arguments: [tx.pure.string(allianceName)] });
    const res: any = await exec(tx, "Create Treasury");
    if (res?.objectChanges) {
      const t = res.objectChanges.find((c: any) => c.type === "created" && c.objectType?.includes("AllianceTreasury"));
      const c = res.objectChanges.find((c: any) => c.type === "created" && c.objectType?.includes("AdminCap"));
      if (t) setTreasuryId(t.objectId);
      if (c) setAdminCapId(c.objectId);
    }
    // Try parsing from effects if objectChanges not available
    if (res?.effects && !res?.objectChanges) {
      setStatus("Create Treasury succeeded (check explorer for object IDs)");
    }
  };

  const createRegistry = async () => {
    const tx = new Transaction();
    tx.moveCall({ target: target("roles", "create_registry"), arguments: [tx.object(adminCapId)] });
    const res: any = await exec(tx, "Create Registry");
    if (res?.objectChanges) {
      const r = res.objectChanges.find((c: any) => c.type === "created" && c.objectType?.includes("RoleRegistry"));
      if (r) setRegistryId(r.objectId);
    }
  };

  const addMember = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("roles", "add_member"),
      arguments: [tx.object(registryId), tx.object(adminCapId), tx.pure.address(memberAddr), tx.pure.u8(Number(memberRole))],
    });
    await exec(tx, "Add Member");
  };

  const deposit = async () => {
    const amountMist = Math.floor(Number(depositAmount) * 1e9);
    const tx = new Transaction();
    const [coin] = tx.splitCoins(tx.gas, [amountMist]);
    tx.moveCall({ target: target("treasury", "deposit"), arguments: [tx.object(treasuryId), coin] });
    await exec(tx, "Deposit");
  };

  const createProposal = async () => {
    const amountMist = Math.floor(Number(proposalAmount) * 1e9);
    const tx = new Transaction();
    tx.moveCall({
      target: target("proposal", "create_proposal"),
      arguments: [
        tx.object(treasuryId), tx.object(registryId), tx.pure.u64(amountMist),
        tx.pure.address(proposalRecipient || account!.address),
        tx.pure.string(proposalPurpose), tx.object("0x6"),
      ],
    });
    const res: any = await exec(tx, "Create Proposal");
    if (res?.objectChanges) {
      const p = res.objectChanges.find((c: any) => c.type === "created" && c.objectType?.includes("BudgetProposal"));
      if (p) setProposalId(p.objectId);
    }
  };

  const signProposal = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("proposal", "sign_proposal"),
      arguments: [tx.object(proposalId), tx.object(registryId), tx.object("0x6")],
    });
    await exec(tx, "Sign Proposal");
  };

  const executeProposal = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("proposal", "execute_proposal"),
      arguments: [tx.object(proposalId), tx.object(treasuryId), tx.object(registryId), tx.object("0x6")],
    });
    await exec(tx, "Execute Proposal");
  };

  const freezeTreasury = async () => {
    const tx = new Transaction();
    tx.moveCall({ target: target("treasury", "emergency_freeze"), arguments: [tx.object(treasuryId)] });
    await exec(tx, "Emergency Freeze");
  };

  const createAgent = async () => {
    const res = await safeFetch(`${BACKEND_URL}/api/agent/create`);
    if (res) { setStatus("Agent created"); fetchBackendData(); }
    else setStatus("Create agent failed — backend offline?");
  };

  const configureSkills = async () => {
    const res = await safeFetch(`${BACKEND_URL}/api/agent/skills`);
    if (res) { setStatus("Skills configured"); fetchBackendData(); }
    else setStatus("Configure failed — backend offline?");
  };

  const agentAutoSign = async () => {
    const res = await safeFetch(`${BACKEND_URL}/api/agent/auto-sign`);
    if (res) { setStatus("Agent auto-signed"); fetchBackendData(); }
    else setStatus("Auto-sign failed — backend offline?");
  };

  // ── Render ─────────────────────────────────────────────────────────

  return (
    <div className="shell">
      <HudBar
        address={account?.address}
        treasuryId={treasuryId}
        frozen={false}
        onConnect={handleConnect}
        onDisconnect={handleDisconnect}
        lastTxDigest={lastTxDigest}
      />

      {status && (
        <div className={`toast ${status.includes("failed") ? "toast--error" : "toast--ok"}`}>
          {status}
        </div>
      )}

      {!account ? (
        <div className="connect-prompt">
          <div className="connect-prompt__title">Access Restricted</div>
          <div className="connect-prompt__text">
            Connect your EVE Vault to access alliance treasury operations.
          </div>
          <button className="btn btn--primary" onClick={handleConnect}>
            Connect Vault
          </button>
        </div>
      ) : (
        <>
          <nav className="tab-nav">
            {TABS.map((tab) => (
              <button
                key={tab.id}
                className={`tab-nav__item ${activeTab === tab.id ? "tab-nav__item--active" : ""}`}
                onClick={() => setActiveTab(tab.id)}
              >
                {tab.label}
              </button>
            ))}
          </nav>

          {activeTab === "setup" && (
            <SetupTab
              treasuryId={treasuryId} adminCapId={adminCapId} registryId={registryId}
              allianceName={allianceName} setAllianceName={setAllianceName}
              memberAddr={memberAddr} setMemberAddr={setMemberAddr}
              memberRole={memberRole} setMemberRole={setMemberRole}
              depositAmount={depositAmount} setDepositAmount={setDepositAmount}
              onCreateTreasury={createTreasury} onCreateRegistry={createRegistry}
              onAddMember={addMember} onDeposit={deposit}
            />
          )}

          {activeTab === "governance" && (
            <GovernanceTab
              treasuryId={treasuryId} registryId={registryId} proposalId={proposalId}
              proposalAmount={proposalAmount} setProposalAmount={setProposalAmount}
              proposalRecipient={proposalRecipient} setProposalRecipient={setProposalRecipient}
              proposalPurpose={proposalPurpose} setProposalPurpose={setProposalPurpose}
              onCreateProposal={createProposal} onSignProposal={signProposal}
              onExecuteProposal={executeProposal} onFreeze={freezeTreasury}
            />
          )}

          {activeTab === "agent" && (
            <AgentTab
              agentMaxAuto={agentMaxAuto} setAgentMaxAuto={setAgentMaxAuto}
              agentDailyLimit={agentDailyLimit} setAgentDailyLimit={setAgentDailyLimit}
              agentProposalId={agentProposalId} setAgentProposalId={setAgentProposalId}
              agentSkills={agentSkills} setAgentSkills={setAgentSkills}
              agentStats={agentStats}
              onCreateAgent={createAgent} onConfigureSkills={configureSkills} onAutoSign={agentAutoSign}
            />
          )}

          {activeTab === "intel" && (
            <IntelTab
              backendOnline={backendOnline} backendLoading={backendLoading}
              proposals={proposals} auditLog={auditLog} killMails={killMails}
              onRefresh={fetchBackendData}
            />
          )}
        </>
      )}
    </div>
  );
}

export default App;
