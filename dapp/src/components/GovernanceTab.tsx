interface GovernanceTabProps {
  treasuryId: string;
  registryId: string;
  proposalId: string;
  proposalAmount: string;
  setProposalAmount: (v: string) => void;
  proposalRecipient: string;
  setProposalRecipient: (v: string) => void;
  proposalPurpose: string;
  setProposalPurpose: (v: string) => void;
  onCreateProposal: () => void;
  onSignProposal: () => void;
  onExecuteProposal: () => void;
  onFreeze: () => void;
}

export function GovernanceTab(props: GovernanceTabProps) {
  const ready = !!props.treasuryId && !!props.registryId;

  if (!ready) {
    return (
      <div className="empty">
        Complete Setup first — create a treasury and registry before submitting proposals.
      </div>
    );
  }

  return (
    <div className="stack">
      {/* Threshold Info */}
      <div className="panel">
        <div className="panel__header">Signature Thresholds</div>
        <table className="data-table">
          <thead>
            <tr>
              <th>Amount</th>
              <th>Required Signatures</th>
            </tr>
          </thead>
          <tbody>
            <tr><td>&lt; 100 SUI</td><td><span className="tag tag--green">2 sigs</span></td></tr>
            <tr><td>100 - 1,000 SUI</td><td><span className="tag tag--amber">3 sigs</span></td></tr>
            <tr><td>&gt; 1,000 SUI</td><td><span className="tag tag--red">4 sigs</span></td></tr>
          </tbody>
        </table>
      </div>

      <div className="grid-2">
        {/* Create Proposal */}
        <div className="panel">
          <div className="panel__header">Submit Proposal</div>
          <div className="stack--sm">
            <div className="row">
              <input
                className="input"
                placeholder="Amount"
                value={props.proposalAmount}
                onChange={(e) => props.setProposalAmount(e.target.value)}
                style={{ flex: 1 }}
              />
              <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>SUI</span>
            </div>
            <input
              className="input"
              placeholder="Recipient address (0x..., defaults to self)"
              value={props.proposalRecipient}
              onChange={(e) => props.setProposalRecipient(e.target.value)}
            />
            <input
              className="input"
              placeholder="Purpose / reason"
              value={props.proposalPurpose}
              onChange={(e) => props.setProposalPurpose(e.target.value)}
            />
            <button className="btn btn--primary" onClick={props.onCreateProposal}>
              Submit Proposal
            </button>
            {props.proposalId && (
              <div className="object-id">Proposal: <span>{props.proposalId.slice(0, 16)}...</span></div>
            )}
          </div>
        </div>

        {/* Sign + Execute */}
        <div className="stack">
          <div className={`panel ${!props.proposalId ? 'panel--disabled' : ''}`}>
            <div className="panel__header panel__header--cyan">Sign Proposal</div>
            <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 12px' }}>
              Each alliance member signs with their own wallet. Signature count must reach the threshold.
            </p>
            <button className="btn" onClick={props.onSignProposal} disabled={!props.proposalId}>
              Add Signature
            </button>
          </div>

          <div className={`panel ${!props.proposalId ? 'panel--disabled' : ''}`}>
            <div className="panel__header panel__header--cyan">Execute Payout</div>
            <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 12px' }}>
              Once threshold met, any member can trigger. Atomic via PTB.
            </p>
            <button className="btn btn--primary" onClick={props.onExecuteProposal} disabled={!props.proposalId}>
              Execute
            </button>
          </div>

          <div className="panel">
            <div className="panel__header panel__header--red">Emergency Freeze</div>
            <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 12px' }}>
              Any member can halt all payouts. Admin required to unfreeze.
            </p>
            <button className="btn btn--danger" onClick={props.onFreeze} disabled={!props.treasuryId}>
              Freeze Treasury
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
