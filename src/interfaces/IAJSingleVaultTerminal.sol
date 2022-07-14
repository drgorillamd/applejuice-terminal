pragma solidity 0.8.6;

import "jbx/interfaces/IJBPayoutRedemptionPaymentTerminal.sol";

import "../structs/Vault.sol";

interface IAJSingleVaultTerminal is IJBPayoutRedemptionPaymentTerminal {
    function setVault(
        uint256 _projectId,
        IERC4626 _vault,
        VaultConfig memory _config,
        uint256 _minWithdraw
    ) external;
}