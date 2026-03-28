interface AgentStats {
  total_auto_signed: number;
  daily_spent: number;
  daily_limit: number;
  max_auto_amount: number;
  skills: string[];
}

interface AgentTabProps {
  agentMaxAuto: string;
  setAgentMaxAuto: (v: string) => void;
  agentDailyLimit: string;
  setAgentDailyLimit: (v: string) => void;
  agentProposalId: string;
  setAgentProposalId: (v: string) => void;
  agentSkills: Record<string, boolean>;
  setAgentSkills: (fn: (prev: Record<string, boolean>) => Record<string, boolean>) => void;
  agentStats: AgentStats | null;
  onCreateAgent: () => void;
  onConfigureSkills: () => void;
  onAutoSign: () => void;
}

const SKILL_DESCRIPTIONS: Record<string, string> = {
  auto_sign: "Auto-approve proposals below max amount",
  rate_limit: "Enforce daily spending cap",
  trusted_list: "Only sign for pre-approved recipients",
  balance_guard: "Block if treasury would drop below reserve",
  cooldown: "Enforce cooldown between same-recipient payouts",
};

export function AgentTab(props: AgentTabProps) {
  return (
    <div className="stack">
      {/* Agent concept */}
      <div className="panel">
        <div className="panel__header panel__header--cyan">Policy Agent</div>
        <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: 0, lineHeight: 1.6 }}>
          An on-chain autonomous governance participant. Not an AI API wrapper — a deterministic,
          auditable rule engine that acts as a co-signer. Configure skills, and the agent will
          auto-approve qualifying proposals 24/7 without human intervention.
        </p>
      </div>

      <div className="grid-2">
        {/* Create Agent */}
        <div className="panel">
          <div className="panel__header">Deploy Agent</div>
          <div className="stack--sm">
            <div>
              <label style={{ fontSize: '10px', textTransform: 'uppercase', letterSpacing: '0.08em', color: 'var(--text-muted)' }}>
                Max Auto-Sign Amount (SUI)
              </label>
              <input
                className="input"
                value={props.agentMaxAuto}
                onChange={(e) => props.setAgentMaxAuto(e.target.value)}
              />
            </div>
            <div>
              <label style={{ fontSize: '10px', textTransform: 'uppercase', letterSpacing: '0.08em', color: 'var(--text-muted)' }}>
                Daily Limit (SUI)
              </label>
              <input
                className="input"
                value={props.agentDailyLimit}
                onChange={(e) => props.setAgentDailyLimit(e.target.value)}
              />
            </div>
            <button className="btn btn--primary" onClick={props.onCreateAgent}>
              Deploy Agent
            </button>
          </div>
        </div>

        {/* Skills */}
        <div className="panel">
          <div className="panel__header">Skill Configuration</div>
          <div className="stack--sm">
            {Object.entries(SKILL_DESCRIPTIONS).map(([key, desc]) => (
              <div className="skill-row" key={key}>
                <div>
                  <div className="skill-row__label">{key.replace(/_/g, " ")}</div>
                  <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>{desc}</div>
                </div>
                <div
                  className={`skill-row__toggle ${props.agentSkills[key] ? 'skill-row__toggle--on' : ''}`}
                  onClick={() => props.setAgentSkills(prev => ({ ...prev, [key]: !prev[key] }))}
                />
              </div>
            ))}
            <button className="btn btn--small" onClick={props.onConfigureSkills}>
              Save Configuration
            </button>
          </div>
        </div>
      </div>

      <div className="grid-2">
        {/* Auto-sign */}
        <div className="panel">
          <div className="panel__header">Agent Auto-Sign</div>
          <div className="stack--sm">
            <input
              className="input"
              placeholder="Proposal ID (0x...)"
              value={props.agentProposalId}
              onChange={(e) => props.setAgentProposalId(e.target.value)}
            />
            <button
              className="btn"
              onClick={props.onAutoSign}
              disabled={!props.agentProposalId}
            >
              Evaluate + Sign
            </button>
          </div>
        </div>

        {/* Stats */}
        <div className="panel">
          <div className="panel__header">Agent Metrics</div>
          {props.agentStats ? (
            <table className="data-table">
              <tbody>
                <tr>
                  <td style={{ color: 'var(--text-muted)' }}>Total Auto-Signed</td>
                  <td style={{ textAlign: 'right' }}>
                    <span className="tag tag--cyan">{props.agentStats.total_auto_signed}</span>
                  </td>
                </tr>
                <tr>
                  <td style={{ color: 'var(--text-muted)' }}>Daily Spent / Limit</td>
                  <td style={{ textAlign: 'right' }}>
                    {props.agentStats.daily_spent} / {props.agentStats.daily_limit} SUI
                  </td>
                </tr>
                <tr>
                  <td style={{ color: 'var(--text-muted)' }}>Max Auto Amount</td>
                  <td style={{ textAlign: 'right' }}>{props.agentStats.max_auto_amount} SUI</td>
                </tr>
              </tbody>
            </table>
          ) : (
            <div className="empty">Deploy an agent above, or start the backend indexer to see metrics.</div>
          )}
        </div>
      </div>
    </div>
  );
}
