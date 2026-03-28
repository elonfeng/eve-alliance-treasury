import dotenv from "dotenv";
dotenv.config();

export const config = {
  packageId: process.env.PACKAGE_ID || "",
  suiRpcUrl:
    process.env.SUI_RPC_URL || "https://fullnode.testnet.sui.io:443",
  worldPackageId:
    process.env.WORLD_PACKAGE_ID ||
    "0xd12a70c74c1e759445d6f209b01d43d860e97fcf2ef72ccbbd00afd828043f75",
  port: Number(process.env.PORT) || 3001,
} as const;
