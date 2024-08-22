import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TokenModule = buildModule("TokenModule", (m) => {
  const lock = m.contract("Token");

  return { lock };
});

export default TokenModule;
