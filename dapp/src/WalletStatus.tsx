import { Box, Container, Flex, Text } from "@radix-ui/themes";
import { useCurrentAccount } from "@mysten/dapp-kit-react";

export function WalletStatus() {
  const account = useCurrentAccount();

  return (
    <Container my="2">
      {account ? (
        <Flex direction="column">
          <Box>Wallet connected</Box>
          <Box>Address: {account.address}</Box>
        </Flex>
      ) : (
        <Text>Wallet not connected</Text>
      )}
    </Container>
  );
}
