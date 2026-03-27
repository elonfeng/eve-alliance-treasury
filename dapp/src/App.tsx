import { useState } from "react";
import {
  Box, Flex, Heading, Button, Text, Card, TextField,
  Badge, Separator, Callout, DataList, Grid,
} from "@radix-ui/themes";
import { abbreviateAddress, useConnection } from "@evefrontier/dapp-kit";
import { useCurrentAccount, useDAppKit } from "@mysten/dapp-kit-react";
import { Transaction } from "@mysten/sui/transactions";

const PACKAGE_ID = import.meta.env.VITE_PACKAGE_ID || "0x0";

function target(module: string, fn: string): `${string}::${string}::${string}` {
  return `${PACKAGE_ID}::${module}::${fn}`;
}

function App() {
  const { handleConnect, handleDisconnect } = useConnection();
  const { signAndExecuteTransaction } = useDAppKit();
  const account = useCurrentAccount();

  // Object IDs (set after creation)
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

  const [status, setStatus] = useState("");
  const [lastTxDigest, setLastTxDigest] = useState("");

  const exec = async (tx: Transaction, label: string) => {
    setStatus(`${label}...`);
    try {
      const result = await signAndExecuteTransaction({
        transaction: tx,
      });
      setLastTxDigest((result as any).digest || "");
      setStatus(`${label} succeeded`);
      return result;
    } catch (e: any) {
      setStatus(`${label} failed: ${e.message?.slice(0, 120)}`);
      return null;
    }
  };

  // ── Actions ────────────────────────────────────────────────────────

  const createTreasury = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("treasury", "create_treasury"),
      arguments: [tx.pure.string(allianceName)],
    });
    const res: any = await exec(tx, "Create Treasury");
    if (res?.objectChanges) {
      const treasury = res.objectChanges.find(
        (c: any) => c.type === "created" && c.objectType?.includes("AllianceTreasury")
      );
      const cap = res.objectChanges.find(
        (c: any) => c.type === "created" && c.objectType?.includes("AdminCap")
      );
      if (treasury) setTreasuryId(treasury.objectId);
      if (cap) setAdminCapId(cap.objectId);
    }
  };

  const createRegistry = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("roles", "create_registry"),
      arguments: [tx.object(adminCapId)],
    });
    const res: any = await exec(tx, "Create Registry");
    if (res?.objectChanges) {
      const reg = res.objectChanges.find(
        (c: any) => c.type === "created" && c.objectType?.includes("RoleRegistry")
      );
      if (reg) setRegistryId(reg.objectId);
    }
  };

  const addMember = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("roles", "add_member"),
      arguments: [
        tx.object(registryId),
        tx.object(adminCapId),
        tx.pure.address(memberAddr),
        tx.pure.u8(Number(memberRole)),
      ],
    });
    await exec(tx, "Add Member");
  };

  const deposit = async () => {
    const amountMist = Math.floor(Number(depositAmount) * 1e9);
    const tx = new Transaction();
    const [coin] = tx.splitCoins(tx.gas, [amountMist]);
    tx.moveCall({
      target: target("treasury", "deposit"),
      arguments: [tx.object(treasuryId), coin],
    });
    await exec(tx, "Deposit");
  };

  const createProposal = async () => {
    const amountMist = Math.floor(Number(proposalAmount) * 1e9);
    const tx = new Transaction();
    tx.moveCall({
      target: target("proposal", "create_proposal"),
      arguments: [
        tx.object(treasuryId),
        tx.object(registryId),
        tx.pure.u64(amountMist),
        tx.pure.address(proposalRecipient || account!.address),
        tx.pure.string(proposalPurpose),
        tx.object("0x6"),
      ],
    });
    const res: any = await exec(tx, "Create Proposal");
    if (res?.objectChanges) {
      const prop = res.objectChanges.find(
        (c: any) => c.type === "created" && c.objectType?.includes("BudgetProposal")
      );
      if (prop) setProposalId(prop.objectId);
    }
  };

  const signProposal = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("proposal", "sign_proposal"),
      arguments: [
        tx.object(proposalId),
        tx.object(registryId),
        tx.object("0x6"),
      ],
    });
    await exec(tx, "Sign Proposal");
  };

  const executeProposal = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("proposal", "execute_proposal"),
      arguments: [
        tx.object(proposalId),
        tx.object(treasuryId),
        tx.object(registryId),
        tx.object("0x6"),
      ],
    });
    await exec(tx, "Execute Proposal");
  };

  const freezeTreasury = async () => {
    const tx = new Transaction();
    tx.moveCall({
      target: target("treasury", "emergency_freeze"),
      arguments: [tx.object(treasuryId)],
    });
    await exec(tx, "Emergency Freeze");
  };

  // ── Render ─────────────────────────────────────────────────────────

  const roleLabels: Record<string, string> = {
    "1": "Commander",
    "2": "Treasurer",
    "4": "Elder",
    "5": "Commander+Elder",
    "8": "Auditor",
  };

  return (
    <Box style={{ padding: "20px", maxWidth: "900px", margin: "0 auto" }}>
      <Flex justify="between" align="center" mb="4">
        <Heading size="6">Alliance Multi-Sig Treasury</Heading>
        <Button
          size="3"
          variant="soft"
          onClick={() =>
            account?.address ? handleDisconnect() : handleConnect()
          }
        >
          {account
            ? abbreviateAddress(account?.address)
            : "Connect EVE Vault"}
        </Button>
      </Flex>

      <Text as="p" color="gray" size="2" mb="4">
        On-chain multi-sig governance for EVE Frontier alliances. No single
        person can move funds.
      </Text>

      {status && (
        <Callout.Root
          color={status.includes("failed") ? "red" : "green"}
          mb="4"
          size="1"
        >
          <Callout.Text>{status}</Callout.Text>
        </Callout.Root>
      )}

      {!account ? (
        <Card size="4" mt="4" style={{ textAlign: "center" }}>
          <Text>Connect your EVE Vault wallet to get started.</Text>
        </Card>
      ) : (
        <Grid columns="2" gap="4" mt="2">
          {/* ─── Left Column: Setup ─── */}
          <Flex direction="column" gap="4">
            {/* Create Treasury */}
            <Card>
              <Heading size="3" mb="3">
                1. Create Treasury
              </Heading>
              <TextField.Root
                placeholder="Alliance name"
                value={allianceName}
                onChange={(e) => setAllianceName(e.target.value)}
                mb="2"
              />
              <Button onClick={createTreasury} disabled={!allianceName}>
                Create Treasury
              </Button>
              {treasuryId && (
                <Text size="1" color="gray" mt="2" as="p">
                  Treasury: {abbreviateAddress(treasuryId)}
                </Text>
              )}
            </Card>

            {/* Create Registry */}
            <Card>
              <Heading size="3" mb="3">
                2. Create Role Registry
              </Heading>
              <Button onClick={createRegistry} disabled={!adminCapId}>
                Create Registry
              </Button>
              {registryId && (
                <Text size="1" color="gray" mt="2" as="p">
                  Registry: {abbreviateAddress(registryId)}
                </Text>
              )}
            </Card>

            {/* Add Member */}
            <Card>
              <Heading size="3" mb="3">
                3. Add Member
              </Heading>
              <Flex direction="column" gap="2">
                <TextField.Root
                  placeholder="Member address (0x...)"
                  value={memberAddr}
                  onChange={(e) => setMemberAddr(e.target.value)}
                />
                <Flex gap="2" wrap="wrap">
                  {Object.entries(roleLabels).map(([val, label]) => (
                    <Badge
                      key={val}
                      color={memberRole === val ? "blue" : "gray"}
                      style={{ cursor: "pointer" }}
                      onClick={() => setMemberRole(val)}
                    >
                      {label} ({val})
                    </Badge>
                  ))}
                </Flex>
                <Button
                  onClick={addMember}
                  disabled={!registryId || !memberAddr}
                >
                  Add Member
                </Button>
              </Flex>
            </Card>

            {/* Deposit */}
            <Card>
              <Heading size="3" mb="3">
                4. Deposit SUI
              </Heading>
              <TextField.Root
                placeholder="Amount (SUI)"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                mb="2"
              />
              <Button onClick={deposit} disabled={!treasuryId}>
                Deposit
              </Button>
            </Card>
          </Flex>

          {/* ─── Right Column: Governance ─── */}
          <Flex direction="column" gap="4">
            {/* Create Proposal */}
            <Card>
              <Heading size="3" mb="3">
                5. Create Budget Proposal
              </Heading>
              <Flex direction="column" gap="2">
                <TextField.Root
                  placeholder="Amount (SUI)"
                  value={proposalAmount}
                  onChange={(e) => setProposalAmount(e.target.value)}
                />
                <TextField.Root
                  placeholder="Recipient (0x..., defaults to self)"
                  value={proposalRecipient}
                  onChange={(e) => setProposalRecipient(e.target.value)}
                />
                <TextField.Root
                  placeholder="Purpose"
                  value={proposalPurpose}
                  onChange={(e) => setProposalPurpose(e.target.value)}
                />
                <Button
                  onClick={createProposal}
                  disabled={!treasuryId || !registryId}
                >
                  Submit Proposal
                </Button>
                {proposalId && (
                  <Text size="1" color="gray" as="p">
                    Proposal: {abbreviateAddress(proposalId)}
                  </Text>
                )}
              </Flex>
            </Card>

            {/* Sign */}
            <Card>
              <Heading size="3" mb="3">
                6. Sign Proposal
              </Heading>
              <Text size="2" color="gray" mb="2" as="p">
                Each alliance member signs with their own wallet. Threshold
                depends on amount.
              </Text>
              <DataList.Root size="1" mb="3">
                <DataList.Item>
                  <DataList.Label>&lt;100 SUI</DataList.Label>
                  <DataList.Value>2 signatures</DataList.Value>
                </DataList.Item>
                <DataList.Item>
                  <DataList.Label>100-1000 SUI</DataList.Label>
                  <DataList.Value>3 signatures</DataList.Value>
                </DataList.Item>
                <DataList.Item>
                  <DataList.Label>&gt;1000 SUI</DataList.Label>
                  <DataList.Value>4 signatures</DataList.Value>
                </DataList.Item>
              </DataList.Root>
              <Button onClick={signProposal} disabled={!proposalId}>
                Sign
              </Button>
            </Card>

            {/* Execute */}
            <Card>
              <Heading size="3" mb="3">
                7. Execute Proposal
              </Heading>
              <Text size="2" color="gray" mb="2" as="p">
                Once threshold met, anyone can trigger execution. Payout is
                atomic via PTB.
              </Text>
              <Button
                onClick={executeProposal}
                disabled={!proposalId}
                color="green"
              >
                Execute Payout
              </Button>
            </Card>

            <Separator size="4" />

            {/* Emergency */}
            <Card>
              <Heading size="3" mb="3" color="red">
                Emergency Freeze
              </Heading>
              <Text size="2" color="gray" mb="2" as="p">
                Any member can freeze the treasury. Stops all payouts until
                admin unfreezes.
              </Text>
              <Button
                onClick={freezeTreasury}
                disabled={!treasuryId}
                color="red"
                variant="outline"
              >
                Freeze Treasury
              </Button>
            </Card>
          </Flex>
        </Grid>
      )}

      {lastTxDigest && (
        <Text size="1" color="gray" mt="4" as="p">
          Last tx:{" "}
          <a
            href={`https://suiscan.xyz/testnet/tx/${lastTxDigest}`}
            target="_blank"
            rel="noreferrer"
          >
            {lastTxDigest.slice(0, 16)}...
          </a>
        </Text>
      )}
    </Box>
  );
}

export default App;
