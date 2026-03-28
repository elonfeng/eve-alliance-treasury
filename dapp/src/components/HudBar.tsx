import { abbreviateAddress } from "@evefrontier/dapp-kit";

interface HudBarProps {
  address: string | undefined;
  treasuryId: string;
  frozen: boolean;
  onConnect: () => void;
  onDisconnect: () => void;
  lastTxDigest: string;
}

export function HudBar({ address, treasuryId, frozen, onConnect, onDisconnect, lastTxDigest }: HudBarProps) {
  return (
    <div className="hud-bar">
      <div className="hud-bar__title">Alliance Treasury</div>

      <div className="hud-bar__stats">
        {treasuryId && (
          <>
            <div className="hud-stat">
              <span className="hud-stat__label">Vault</span>
              <span className="hud-stat__value hud-stat__value--cyan">
                {abbreviateAddress(treasuryId)}
              </span>
            </div>
            <div className="hud-stat">
              <span className="hud-stat__label">Status</span>
              <span className={`hud-stat__value ${frozen ? 'hud-stat__value--red' : 'hud-stat__value--green'}`}>
                {frozen ? 'FROZEN' : 'ACTIVE'}
              </span>
            </div>
          </>
        )}

        {lastTxDigest && (
          <div className="hud-stat">
            <span className="hud-stat__label">Last TX</span>
            <a
              href={`https://suiscan.xyz/testnet/tx/${lastTxDigest}`}
              target="_blank"
              rel="noreferrer"
              className="hud-stat__value hud-stat__value--cyan"
              style={{ textDecoration: 'none', fontSize: '12px' }}
            >
              {lastTxDigest.slice(0, 10)}...
            </a>
          </div>
        )}

        <div
          className="wallet-badge"
          onClick={() => address ? onDisconnect() : onConnect()}
        >
          <span className={`wallet-badge__dot ${!address ? 'wallet-badge__dot--disconnected' : ''}`} />
          {address ? abbreviateAddress(address) : 'CONNECT VAULT'}
        </div>
      </div>
    </div>
  );
}
