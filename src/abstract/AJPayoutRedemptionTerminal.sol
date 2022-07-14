// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "jbx/libraries/JBOperations.sol";
import "jbx/abstract/JBPayoutRedemptionPaymentTerminal.sol";

import "../enums/AJReserveReason.sol";
import "../enums/AJAssignReason.sol";

/*
Thirst is the craving for potable fluids, resulting in the basic instinct of animals to drink.
It is an essential mechanism involved in fluid balance.
*/

abstract contract AJPayoutRedemptionTerminal is
    JBPayoutRedemptionPaymentTerminal
{
    // A library that parses the packed funding cycle metadata into a friendlier format.
    using JBFundingCycleMetadataResolver for JBFundingCycle;

    /**
        @notice Adds the `_amount` of assets to the projects accounting and allows the funds to be assigned
    */
    function _assignAssets(
        uint256 _projectId,
        uint256 _amount,
        AJAssignReason _reason
    ) internal virtual;

    /**
        @notice Removes the `_amount` of assets from the projects accounting and reserves the `_amount` in this contract
        @dev Revert if its not possible to reserve the `_amount`
    */
    function _reserveAssets(
        uint256 _projectId,
        uint256 _amount,
        AJReserveReason _reason
    ) internal virtual;

    //*********************************************************************//
    // ------------------------- internal overrides ---------------------- //
    //*********************************************************************//

    /**
    @notice
    Distributes payouts for a project with the distribution limit of its current funding cycle.

    @dev
    Payouts are sent to the preprogrammed splits. Any leftover is sent to the project's owner.

    @dev
    Anyone can distribute payouts on a project's behalf. The project can preconfigure a wildcard split that is used to send funds to msg.sender. This can be used to incentivize calling this function.

    @dev
    All funds distributed outside of this contract or any feeless terminals incure the protocol fee.

    @param _projectId The ID of the project having its payouts distributed.
    @param _amount The amount of terminal tokens to distribute, as a fixed point number with same number of decimals as this terminal.
    @param _currency The expected currency of the amount being distributed. Must match the project's current funding cycle's distribution limit currency.
    @param _minReturnedTokens The minimum number of terminal tokens that the `_amount` should be valued at in terms of this terminal's currency, as a fixed point number with the same number of decimals as this terminal.
    @param _memo A memo to pass along to the emitted event.

    @return netLeftoverDistributionAmount The amount that was sent to the project owner, as a fixed point number with the same amount of decimals as this terminal.
  */
    function _distributePayoutsOf(
        uint256 _projectId,
        uint256 _amount,
        uint256 _currency,
        uint256 _minReturnedTokens,
        string calldata _memo
    )
        internal
        virtual
        override
        returns (uint256 netLeftoverDistributionAmount)
    {
        // Record the distribution.
        (
            JBFundingCycle memory _fundingCycle,
            uint256 _distributedAmount
        ) = store.recordDistributionFor(_projectId, _amount, _currency);

        // Prepare the assets
        _reserveAssets(
            _projectId,
            _distributedAmount,
            AJReserveReason.DistributePayoutsOf
        );

        // The amount being distributed must be at least as much as was expected.
        if (_distributedAmount < _minReturnedTokens)
            revert INADEQUATE_DISTRIBUTION_AMOUNT();

        // Get a reference to the project owner, which will receive tokens from paying the platform fee
        // and receive any extra distributable funds not allocated to payout splits.
        address payable _projectOwner = payable(projects.ownerOf(_projectId));

        // Define variables that will be needed outside the scoped section below.
        // Keep a reference to the fee amount that was paid.
        uint256 _fee;

        // Scoped section prevents stack too deep. `_feeDiscount`, `_feeEligibleDistributionAmount`, and `_leftoverDistributionAmount` only used within scope.
        {
            // Get the amount of discount that should be applied to any fees taken.
            // If the fee is zero, set the discount to 100% for convinience.
            uint256 _feeDiscount = fee == 0
                ? JBConstants.MAX_FEE_DISCOUNT
                : _currentFeeDiscount(_projectId);

            // The amount distributed that is eligible for incurring fees.
            uint256 _feeEligibleDistributionAmount;

            // The amount leftover after distributing to the splits.
            uint256 _leftoverDistributionAmount;

            // Payout to splits and get a reference to the leftover transfer amount after all splits have been paid.
            // Also get a reference to the amount that was distributed to splits from which fees should be taken.
            (
                _leftoverDistributionAmount,
                _feeEligibleDistributionAmount
            ) = _distributeToPayoutSplitsOf(
                _projectId,
                _fundingCycle.configuration,
                payoutSplitsGroup,
                _distributedAmount,
                _feeDiscount
            );

            // Leftover distribution amount is also eligible for a fee since the funds are going out of the ecosystem to _beneficiary.
            _feeEligibleDistributionAmount += _leftoverDistributionAmount;

            // Take the fee.
            _fee = _feeDiscount == JBConstants.MAX_FEE_DISCOUNT ||
                _feeEligibleDistributionAmount == 0
                ? 0
                : _takeFeeFrom(
                    _projectId,
                    _fundingCycle,
                    _feeEligibleDistributionAmount,
                    _projectOwner,
                    _feeDiscount
                );

            // Get a reference to how much to distribute to the project owner, which is the leftover amount minus any fees.
            netLeftoverDistributionAmount = _leftoverDistributionAmount == 0
                ? 0
                : _leftoverDistributionAmount -
                    _feeAmount(_leftoverDistributionAmount, fee, _feeDiscount);

            // Transfer any remaining balance to the project owner.
            if (netLeftoverDistributionAmount > 0)
                _transferFrom(
                    address(this),
                    _projectOwner,
                    netLeftoverDistributionAmount
                );
        }

        emit DistributePayouts(
            _fundingCycle.configuration,
            _fundingCycle.number,
            _projectId,
            _projectOwner,
            _amount,
            _distributedAmount,
            _fee,
            netLeftoverDistributionAmount,
            _memo,
            msg.sender
        );
    }

    /**
    @notice
    Contribute tokens to a project.

    @param _amount The amount of terminal tokens being received, as a fixed point number with the same amount of decimals as this terminal. If this terminal's token is ETH, this is ignored and msg.value is used in its place.
    @param _payer The address making the payment.
    @param _projectId The ID of the project being paid.
    @param _beneficiary The address to mint tokens for and pass along to the funding cycle's delegate.
    @param _minReturnedTokens The minimum number of project tokens expected in return, as a fixed point number with the same amount of decimals as this terminal.
    @param _preferClaimedTokens A flag indicating whether the request prefers to mint project tokens into the beneficiaries wallet rather than leaving them unclaimed. This is only possible if the project has an attached token contract. Leaving them unclaimed saves gas.
    @param _memo A memo to pass along to the emitted event, and passed along the the funding cycle's data source and delegate.  A data source can alter the memo before emitting in the event and forwarding to the delegate.
    @param _metadata Bytes to send along to the data source, delegate, and emitted event, if provided.

    @return beneficiaryTokenCount The number of tokens minted for the beneficiary, as a fixed point number with 18 decimals.
  */
    function _pay(
        uint256 _amount,
        address _payer,
        uint256 _projectId,
        address _beneficiary,
        uint256 _minReturnedTokens,
        bool _preferClaimedTokens,
        string memory _memo,
        bytes memory _metadata
    ) internal virtual override returns (uint256 beneficiaryTokenCount) {
        beneficiaryTokenCount = super._pay(
            _amount,
            _payer,
            _projectId,
            _beneficiary,
            _minReturnedTokens,
            _preferClaimedTokens,
            _memo,
            _metadata
        );

        _assignAssets(_projectId, _amount, AJAssignReason.Pay);
    }

    /**
    @notice
    Receives funds belonging to the specified project.
    @param _projectId The ID of the project to which the funds received belong.
    @param _amount The amount of tokens to add, as a fixed point number with the same number of decimals as this terminal. If this is an ETH terminal, this is ignored and msg.value is used instead.
    @param _shouldRefundHeldFees A flag indicating if held fees should be refunded based on the amount being added.
    @param _memo A memo to pass along to the emitted event.
    @param _metadata Extra data to pass along to the emitted event.
  */
    function _addToBalanceOf(
        uint256 _projectId,
        uint256 _amount,
        bool _shouldRefundHeldFees,
        string memory _memo,
        bytes memory _metadata
    ) internal virtual override {
        super._addToBalanceOf(
            _projectId,
            _amount,
            _shouldRefundHeldFees,
            _memo,
            _metadata
        );

        _assignAssets(_projectId, _amount, AJAssignReason.AddToBalanceOf);
    }

    /**
    @notice
    Holders can redeem their tokens to claim the project's overflowed tokens, or to trigger rules determined by the project's current funding cycle's data source.

    @dev
    Only a token holder or a designated operator can redeem its tokens. Slight rename from original so we dont have to make it `internal virtual`

    @param _holder The account to redeem tokens for.
    @param _projectId The ID of the project to which the tokens being redeemed belong.
    @param _tokenCount The number of project tokens to redeem, as a fixed point number with 18 decimals.
    @param _minReturnedTokens The minimum amount of terminal tokens expected in return, as a fixed point number with the same amount of decimals as the terminal.
    @param _beneficiary The address to send the terminal tokens to.
    @param _memo A memo to pass along to the emitted event.
    @param _metadata Bytes to send along to the data source, delegate, and emitted event, if provided.

    @return reclaimAmount The amount of terminal tokens that the project tokens were redeemed for, as a fixed point number with 18 decimals.
  */
    function _redeemTokensOf(
        address _holder,
        uint256 _projectId,
        uint256 _tokenCount,
        uint256 _minReturnedTokens,
        address payable _beneficiary,
        string memory _memo,
        bytes memory _metadata
    ) internal virtual override returns (uint256 reclaimAmount) {
        // Can't send reclaimed funds to the zero address.
        if (_beneficiary == address(0)) revert REDEEM_TO_ZERO_ADDRESS();

        // Define variables that will be needed outside the scoped section below.
        // Keep a reference to the funding cycle during which the redemption is being made.
        JBFundingCycle memory _fundingCycle;

        // Scoped section prevents stack too deep. `_delegate` only used within scope.
        {
            IJBRedemptionDelegate _delegate;

            // Record the redemption.
            (_fundingCycle, reclaimAmount, _delegate, _memo) = store
                .recordRedemptionFor(
                    _holder,
                    _projectId,
                    _tokenCount,
                    _memo,
                    _metadata
                );

            // The amount being reclaimed must be at least as much as was expected.
            if (reclaimAmount < _minReturnedTokens)
                revert INADEQUATE_RECLAIM_AMOUNT();

            // Burn the project tokens.
            if (_tokenCount > 0)
                IJBController(directory.controllerOf(_projectId)).burnTokensOf(
                    _holder,
                    _projectId,
                    _tokenCount,
                    "",
                    false
                );

            // If a delegate was returned by the data source, issue a callback to it.
            if (_delegate != IJBRedemptionDelegate(address(0))) {
                JBDidRedeemData memory _data = JBDidRedeemData(
                    _holder,
                    _projectId,
                    _fundingCycle.configuration,
                    _tokenCount,
                    JBTokenAmount(token, reclaimAmount, decimals, currency),
                    _beneficiary,
                    _memo,
                    _metadata
                );
                _delegate.didRedeem(_data);
                emit DelegateDidRedeem(_delegate, _data, msg.sender);
            }
        }

        // Send the reclaimed funds to the beneficiary.
        if (reclaimAmount > 0) {
            _reserveAssets(
                _projectId,
                reclaimAmount,
                AJReserveReason.RedeemTokensOf
            );
            _transferFrom(address(this), _beneficiary, reclaimAmount);
        }

        emit RedeemTokens(
            _fundingCycle.configuration,
            _fundingCycle.number,
            _projectId,
            _holder,
            _beneficiary,
            _tokenCount,
            reclaimAmount,
            _memo,
            _metadata,
            msg.sender
        );
    }

    /**
    @notice
    Allows a project to send funds from its overflow up to the preconfigured allowance.

    @dev
    Only a project's owner or a designated operator can use its allowance.

    @dev
    Incurs the protocol fee.

    @param _projectId The ID of the project to use the allowance of.
    @param _amount The amount of terminal tokens to use from this project's current allowance, as a fixed point number with the same amount of decimals as this terminal.
    @param _currency The expected currency of the amount being distributed. Must match the project's current funding cycle's overflow allowance currency.
    @param _minReturnedTokens The minimum number of tokens that the `_amount` should be valued at in terms of this terminal's currency, as a fixed point number with 18 decimals.
    @param _beneficiary The address to send the funds to.
    @param _memo A memo to pass along to the emitted event.

    @return netDistributedAmount The amount of tokens that was distributed to the beneficiary, as a fixed point number with the same amount of decimals as the terminal.
  */
    function _useAllowanceOf(
        uint256 _projectId,
        uint256 _amount,
        uint256 _currency,
        uint256 _minReturnedTokens,
        address payable _beneficiary,
        string memory _memo
    ) internal virtual override returns (uint256 netDistributedAmount) {
        // Record the use of the allowance.
        (
            JBFundingCycle memory _fundingCycle,
            uint256 _distributedAmount
        ) = store.recordUsedAllowanceOf(_projectId, _amount, _currency);

        // The amount being withdrawn must be at least as much as was expected.
        if (_distributedAmount < _minReturnedTokens)
            revert INADEQUATE_DISTRIBUTION_AMOUNT();

        _reserveAssets(
            _projectId,
            _distributedAmount,
            AJReserveReason.UseAllowanceOf
        );

        // Scoped section prevents stack too deep. `_fee`, `_projectOwner`, `_feeDiscount`, and `_netAmount` only used within scope.
        {
            // Keep a reference to the fee amount that was paid.
            uint256 _fee;

            // Get a reference to the project owner, which will receive tokens from paying the platform fee.
            address _projectOwner = projects.ownerOf(_projectId);

            // Get the amount of discount that should be applied to any fees taken.
            // If the fee is zero, set the discount to 100% for convinience.
            uint256 _feeDiscount = fee == 0
                ? JBConstants.MAX_FEE_DISCOUNT
                : _currentFeeDiscount(_projectId);

            // Take a fee from the `_distributedAmount`, if needed.
            _fee = _feeDiscount == JBConstants.MAX_FEE_DISCOUNT
                ? 0
                : _takeFeeFrom(
                    _projectId,
                    _fundingCycle,
                    _distributedAmount,
                    _projectOwner,
                    _feeDiscount
                );

            // The net amount is the withdrawn amount without the fee.
            netDistributedAmount = _distributedAmount - _fee;

            // Transfer any remaining balance to the beneficiary.
            if (netDistributedAmount > 0)
                _transferFrom(
                    address(this),
                    _beneficiary,
                    netDistributedAmount
                );
        }

        emit UseAllowance(
            _fundingCycle.configuration,
            _fundingCycle.number,
            _projectId,
            _beneficiary,
            _amount,
            _distributedAmount,
            netDistributedAmount,
            _memo,
            msg.sender
        );
    }
}
