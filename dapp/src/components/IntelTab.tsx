interface BackendProposal {
  id: string;
  purpose: string;
  amount: string;
  status: string;
  created_at: string;
}

interface AuditEntry {
  proposal_id: string;
  purpose: string;
  proposer: string;
  recipient: string;
  amount: string;
  executor: string;
  executed_at: string;
}

interface KillMail {
  killer_id: string;
  victim_id: string;
  loss_type: string;
  kill_timestamp: string;
}

interface IntelTabProps {
  backendOnline: boolean | null;
  backendLoading: boolean;
  proposals: BackendProposal[];
  auditLog: AuditEntry[];
  killMails: KillMail[];
  onRefresh: () => void;
}

function statusTag(status: string) {
  const cls = status === "executed" ? "tag--green" : status === "pending" ? "tag--amber" : "tag--muted";
  return <span className={`tag ${cls}`}>{status}</span>;
}

export function IntelTab(props: IntelTabProps) {
  return (
    <div className="stack">
      {/* Status bar */}
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div className="row">
          <span className={`tag ${props.backendOnline ? 'tag--green' : 'tag--red'}`}>
            {props.backendOnline === null ? 'CHECKING' : props.backendOnline ? 'INDEXER ONLINE' : 'INDEXER OFFLINE'}
          </span>
          {props.backendLoading && (
            <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Syncing...</span>
          )}
        </div>
        <button className="btn btn--small" onClick={props.onRefresh}>Refresh</button>
      </div>

      {props.backendOnline === false && (
        <div className="toast toast--info">
          Backend indexer is offline. Start it with: cd backend && npm run dev
        </div>
      )}

      <div className="grid-2">
        {/* Proposals */}
        <div className="panel">
          <div className="panel__header">Recent Proposals</div>
          {props.proposals.length === 0 ? (
            <div className="empty">No proposals indexed yet. Create a proposal in the Governance tab, or start the backend indexer.</div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>ID</th>
                  <th>Purpose</th>
                  <th>Amount</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {props.proposals.map((p) => (
                  <tr key={p.id}>
                    <td style={{ fontFamily: 'var(--font-body)', fontSize: '11px' }}>{p.id.slice(0, 8)}...</td>
                    <td>{p.purpose}</td>
                    <td>{(Number(p.amount) / 1e9).toFixed(3)} SUI</td>
                    <td>{statusTag(p.status)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* Audit */}
        <div className="panel">
          <div className="panel__header">Audit Log</div>
          {props.auditLog.length === 0 ? (
            <div className="empty">Audit entries appear here after proposals are executed.</div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Purpose</th>
                  <th>Proposer</th>
                  <th>Amount</th>
                  <th>Time</th>
                </tr>
              </thead>
              <tbody>
                {props.auditLog.map((e, i) => (
                  <tr key={i}>
                    <td>{e.purpose}</td>
                    <td style={{ fontSize: '11px' }}>{e.proposer?.slice(0, 8) || '—'}...</td>
                    <td>{(Number(e.amount) / 1e9).toFixed(3)} SUI</td>
                    <td style={{ fontSize: '11px' }}>{e.executed_at?.slice(0, 10) || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* KillMail Feed */}
      <div className="panel">
        <div className="panel__header panel__header--red">KillMail Feed</div>
        {props.killMails.length === 0 ? (
          <div className="empty">No killmails detected. KillMails require PvP kills + manual reporting in-game.</div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Killer</th>
                <th>Victim</th>
                <th>Timestamp</th>
              </tr>
            </thead>
            <tbody>
              {props.killMails.map((km, i) => (
                <tr key={i}>
                  <td style={{ fontSize: '11px' }}>{km.killer_id?.slice(0, 10) || '—'}...</td>
                  <td style={{ fontSize: '11px' }}>{km.victim_id?.slice(0, 10) || '—'}...</td>
                  <td style={{ fontSize: '11px' }}>{km.kill_timestamp?.slice(0, 10) || '—'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
