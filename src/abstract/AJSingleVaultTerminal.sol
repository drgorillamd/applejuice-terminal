// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "jbx/libraries/JBOperations.sol";

import "../interfaces/IERC4626.sol";
import "./AJPayoutRedemptionTerminal.sol";
import "../enums/AJReserveReason.sol";
import "../enums/AJAssignReason.sol";
import "../structs/Vault.sol";

// TODO: Add reentrency protection
// TODO: Have withdraw/deposit check the weight of 1 wei share (as to not try and deposit/withdraw 0.5 wei share)
abstract contract AJSingleVaultTerminal is AJPayoutRedemptionTerminal {
    mapping(uint256 => Vault) public projectVault;

    // TODO: Change required `JBOperations` permission to one specific to this action
    function setVault(
        uint256 _projectId,
        IERC4626 _vault,
        VaultConfig memory _config,
        uint256 _minWithdraw
    )
        external
        requirePermission(
            projects.ownerOf(_projectId),
            _projectId,
            JBOperations.RECONFIGURE
        )
    {
        Vault storage _currentVault = projectVault[_projectId];

        if (address(_currentVault.impl) == address(0)) {
            // No current vault is set
            _currentVault.impl = _vault;
            _currentVault.config = _config;
        } else if (address(_currentVault.impl) == address(_vault)) {
            // The implementation stays the same, the config changes
            _currentVault.config = _config;
        } else {
            // Update the shares accounting before the redeem
            uint256 _shares = _currentVault.state.shares;
            _currentVault.state.shares = 0;




            // TODO: If `impl` is 0 address, `targetLocalBalancePPM` has to be 1M
            _currentVault.impl = _vault;
            _currentVault.config = _config;
        }
        // TODO: Check `_targetLocalBalanceDelta` to see if we need to deposit/withdraw
    }

    /**
        @notice Withdraw from the vault
    */
    function _exitVault(Vault storage _currentVault, uint256 _minReceived) internal {
        // Track how many share we should redeem
        uint256 _shares = _currentVault.state.shares;
        // Set the shares to 0
        delete _currentVault.state.shares;

        // Redeem all available shares
        uint256 _assetsReceived = _redeem(
            _currentVault,
            _shares
        );

        // Verify we received enough
        if (_assetsReceived < _minReceived) {
            // TODO: Custom error
            revert();
        }

        // Update the assets accounting with the received assets
        _currentVault.state.localBalance += _assetsReceived;
    }

    /**
        @notice Adds the `_amount` of assets to the projects accounting and allows the funds to be assigned
    */
    function _assignAssets(
        uint256 _projectId,
        uint256 _amount,
        AJAssignReason _reason
    ) internal virtual override {
        Vault storage _vault = projectVault[_projectId];

        // We never deposit on 'Pay' or 'FeesPaid' to keep them low gas
        if (address(_vault.impl) != address(0) && _reason != AJAssignReason.FeesPaid) {
            int256 _targetDelta = _targetLocalBalanceDelta(
                _vault,
                int256(_amount)
            );

            // Depositing more (usually) does not increase the gas cost
            // so we use this opportunity to fill up to the target amount
            if (_targetDelta > 0) {
                // Make sure we can afford atleast 1 vault share
                // (this is only not the case if a few wei gets assigned)
                if (_vault.impl.convertToShares(uint256(_targetDelta)) != 0){
                    // Calculate the new local balance for the project
                    _vault.state.localBalance =
                        _vault.state.localBalance +
                        _amount -
                        uint256(_targetDelta);
                    // Perform the deposit and update the vault shares
                    _vault.state.shares += _deposit(_vault, uint256(_targetDelta));
                    return;
                }
            }
        }

        _vault.state.localBalance += _amount;
        return;
    }

    /**
        @notice Removes the `_amount` of assets from the projects accounting and reserves the `_amount` in this contract
        @dev Revert if its not possible to reserve the `_amount`
    */
    function _reserveAssets(
        uint256 _projectId,
        uint256 _amount,
        AJReserveReason _reason
    ) internal virtual override {
        Vault storage _vault = projectVault[_projectId];

        // If no vault is set we have to use the local balance
        // Either we have to withdraw from the vault, or this is a `DistributePayoutsOf` and we do housekeeping
        if (
            address(_vault.impl) != address(0) &&
            ( _amount > _vault.state.localBalance ||
            _reason == AJReserveReason.DistributePayoutsOf)
        ) {
            // Withdrawing more (usually) does not increase the gas cost
            // so we use this opportunity to fill up to the target amount
            int256 _targetDelta = _targetLocalBalanceDelta(
                _vault,
                -int256(_amount)
            );
            // we should always have enough shares to do this since we just checked how much we have in the vault
            if (_targetDelta < 0) {
                // Update the accounting
                _vault.state.localBalance =
                    _vault.state.localBalance +
                    uint256(-_targetDelta) -
                    _amount;

                // Perform the withdraw
                // This can never withdraw more than the project has since it will underflow
                _vault.state.shares -= _withdraw(_vault, uint256(-_targetDelta));
                return;
            }
        }

        // The other operations such as RedeemTokensOf, UseAllowanceOf and ProcessFees use the local balance
        _vault.state.localBalance -= _amount;
    }

    function currentEthOverflowOf(uint256 _projectId)
        external
        view
        virtual
        override
        returns (uint256 _assets)
    {
        Vault storage _vault = projectVault[_projectId];
        _assets = _vault.state.localBalance;

        // If an vault is set, get the amount of assets that we have deposited
        if (address(_vault.impl) != address(0)) {
            _assets += _vault.impl.previewRedeem(_vault.state.shares);
        }
        // TODO: convert to ETH(?)
    }

    function targetLocalBalanceDelta(uint256 _projectId, int256 _amount)
        external
        returns (int256)
    {
        Vault storage _vault = projectVault[_projectId];
        return _targetLocalBalanceDelta(_vault, _amount);
    }

    function _targetLocalBalanceDelta(Vault storage _vault, int256 _change)
        internal
        returns (int256 delta)
    {
        // Get the amount of assets in the vault
        // TODO: Should we use `convertToAssets` or `previewRedeem` here?
        uint256 _vaultAssets = _vault.impl.convertToAssets(_vault.state.shares);
        uint256 _totalAssets = _vault.state.localBalance + _vaultAssets;

        if (_change >= 0) {
            // Add change to the total balance
            _totalAssets += uint256(_change);
        } else {
            // Subtract the abs of change from the total balance
            _totalAssets -= uint256(-_change);
        }

        // calculate the target local amount
        uint256 _targetLocalBalance = _totalAssets * _vault.config.targetLocalBalancePPM / 1_000_000;

        delta =
            int256(_vault.state.localBalance) +
            _change -
            int256(_targetLocalBalance);
    }

    function _withdraw(Vault storage _vault, uint256 _assetAmount)
        internal
        virtual
        returns (uint256 sharesCost);

    function _redeem(Vault storage _vault, uint256 _sharesAmount)
        internal
        virtual
        returns (uint256 assetsReceived);

    function _deposit(Vault storage _vault, uint256 _assetAmount)
        internal
        virtual
        returns (uint256 sharesReceived);
}