interface SetupTabProps {
  treasuryId: string;
  adminCapId: string;
  registryId: string;
  allianceName: string;
  setAllianceName: (v: string) => void;
  memberAddr: string;
  setMemberAddr: (v: string) => void;
  memberRole: string;
  setMemberRole: (v: string) => void;
  depositAmount: string;
  setDepositAmount: (v: string) => void;
  onCreateTreasury: () => void;
  onCreateRegistry: () => void;
  onAddMember: () => void;
  onDeposit: () => void;
}

const ROLES: Record<string, string> = {
  "1": "Commander",
  "2": "Treasurer",
  "4": "Elder",
  "5": "Cmd+Elder",
  "8": "Auditor",
};

export function SetupTab(props: SetupTabProps) {
  const step =
    !props.treasuryId ? 0 :
    !props.registryId ? 1 :
    2; // members + deposit always available after registry

  const steps = ["Treasury", "Registry", "Members", "Deposit"];

  return (
    <div>
      {/* Step indicator */}
      <div className="steps">
        {steps.map((label, i) => (
          <div
            key={label}
            className={`step ${i === step ? 'step--active' : ''} ${i < step ? 'step--done' : ''}`}
          >
            <span className="step__number">{i < step ? '\u2713' : i + 1}</span>
            <span className="step__label">{label}</span>
          </div>
        ))}
      </div>

      <div className="grid-2">
        {/* Create Treasury */}
        <div className={`panel ${step !== 0 && props.treasuryId ? '' : step !== 0 ? 'panel--disabled' : ''}`}>
          <div className="panel__header">Create Treasury</div>
          <div className="stack--sm">
            <input
              className="input"
              placeholder="Alliance name"
              value={props.allianceName}
              onChange={(e) => props.setAllianceName(e.target.value)}
            />
            <button
              className="btn btn--primary"
              onClick={props.onCreateTreasury}
              disabled={!props.allianceName || !!props.treasuryId}
            >
              {props.treasuryId ? 'Created' : 'Initialize Vault'}
            </button>
            {props.treasuryId && (
              <div className="object-id">Vault: <span>{props.treasuryId.slice(0, 16)}...</span></div>
            )}
          </div>
        </div>

        {/* Create Registry */}
        <div className={`panel ${step < 1 ? 'panel--disabled' : ''}`}>
          <div className="panel__header">Role Registry</div>
          <div className="stack--sm">
            <p style={{ fontSize: '12px', color: 'var(--text-muted)', margin: '0 0 8px' }}>
              Stores member addresses and role permissions for this alliance.
            </p>
            <button
              className="btn btn--primary"
              onClick={props.onCreateRegistry}
              disabled={!props.adminCapId || !!props.registryId}
            >
              {props.registryId ? 'Created' : 'Deploy Registry'}
            </button>
            {props.registryId && (
              <div className="object-id">Registry: <span>{props.registryId.slice(0, 16)}...</span></div>
            )}
          </div>
        </div>

        {/* Add Member */}
        <div className={`panel ${step < 2 ? 'panel--disabled' : ''}`}>
          <div className="panel__header">Add Member</div>
          <div className="stack--sm">
            <input
              className="input"
              placeholder="Wallet address (0x...)"
              value={props.memberAddr}
              onChange={(e) => props.setMemberAddr(e.target.value)}
            />
            <div className="role-selector">
              {Object.entries(ROLES).map(([val, label]) => (
                <button
                  key={val}
                  className={`role-chip ${props.memberRole === val ? 'role-chip--active' : ''}`}
                  onClick={() => props.setMemberRole(val)}
                >
                  {label}
                </button>
              ))}
            </div>
            <button
              className="btn"
              onClick={props.onAddMember}
              disabled={!props.registryId || !props.memberAddr}
            >
              Register Member
            </button>
          </div>
        </div>

        {/* Deposit */}
        <div className={`panel ${step < 2 ? 'panel--disabled' : ''}`}>
          <div className="panel__header">Deposit SUI</div>
          <div className="stack--sm">
            <div className="row">
              <input
                className="input"
                placeholder="Amount"
                value={props.depositAmount}
                onChange={(e) => props.setDepositAmount(e.target.value)}
                style={{ flex: 1 }}
              />
              <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>SUI</span>
            </div>
            <button
              className="btn btn--primary"
              onClick={props.onDeposit}
              disabled={!props.treasuryId}
            >
              Fund Treasury
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
