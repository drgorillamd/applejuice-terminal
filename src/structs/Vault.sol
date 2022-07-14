pragma solidity 0.8.6;

import "../interfaces/IERC4626.sol";
import "./VaultConfig.sol";
import "./VaultState.sol";

struct Vault {
    IERC4626 impl;
    VaultConfig config;
    VaultState state;
}