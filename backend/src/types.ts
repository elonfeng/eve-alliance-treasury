// ---- DB row types ----

export interface ProposalRow {
  id: string;
  treasury_id: string;
  proposer: string;
  amount: string; // stored as text to avoid JS integer precision issues with MIST
  recipient: string;
  purpose: string;
  required_sigs: number;
  status: string; // "Pending" | "Executed" | "Expired"
  created_at: string; // ISO-8601
  expires_at: string; // ISO-8601
}

export interface SignatureRow {
  proposal_id: string;
  signer: string;
  signed_at: string;
}

export interface PayoutRow {
  proposal_id: string;
  treasury_id: string;
  recipient: string;
  amount: string;
  executor: string;
  executed_at: string;
}

export interface KillmailRow {
  id: string;
  killer_id: string;
  victim_id: string;
  loss_type: string;
  solar_system_id: string;
  kill_timestamp: string;
}

export interface JumpRow {
  source_gate_id: string;
  dest_gate_id: string;
  character_id: string;
  timestamp: string;
}

// ---- On-chain parsed event types ----

export interface ProposalCreatedEvent {
  proposal_id: string;
  treasury_id: string;
  proposer: string;
  amount: string;
  recipient: string;
  purpose: string;
  required_count: string;
  expires_at: string;
}

export interface ProposalSignedEvent {
  proposal_id: string;
  signer: string;
  signature_count: string;
  required_count: string;
}

export interface ProposalExecutedEvent {
  proposal_id: string;
  treasury_id: string;
  executor: string;
  recipient: string;
  amount: string;
}

export interface ProposalMarkedExpiredEvent {
  proposal_id: string;
  marked_by: string;
}

export interface AgentAutoSignedEvent {
  proposal_id: string;
  agent_id: string;
  signature_count: string;
  required_count: string;
}

export interface DepositedEvent {
  treasury_id: string;
  depositor: string;
  amount: string;
  new_balance: string;
}

export interface PaidOutEvent {
  treasury_id: string;
  recipient: string;
  amount: string;
  proposal_id: string;
}

// EVE world events

export interface KillmailCreatedEvent {
  id: string;
  killer_character_id: string;
  victim_character_id: string;
  loss_type: string;
  solar_system_id: string;
  timestamp: string;
}

export interface JumpEventData {
  source_gate_id: string;
  dest_gate_id: string;
  character_id: string;
  timestamp: string;
}

// ---- Cursor tracking ----

export interface CursorRow {
  key: string;
  tx_digest: string;
  event_seq: string;
}
