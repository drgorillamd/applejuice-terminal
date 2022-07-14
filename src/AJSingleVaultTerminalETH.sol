pragma solidity 0.8.6;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./abstract/AJSingleVaultTerminal.sol";
import "./interfaces/IWETH.sol";

// TODO: Add support for paying with wETH (?)
contract AJSingleVaultTerminalETH is AJSingleVaultTerminal {
    IWETH immutable wETH;

    /**
  @param _baseWeightCurrency The currency to base token issuance on.
  @param _operatorStore A contract storing operator assignments.
  @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
  @param _directory A contract storing directories of terminals and controllers for each project.
  @param _splitsStore A contract that stores splits for each project.
  @param _prices A contract that exposes price feeds.
  @param _store A contract that stores the terminal's data.
  @param _wETH The wETH instance to use
  @param _owner The address that will own this contract.
*/
    constructor(
        uint256 _baseWeightCurrency,
        IJBOperatorStore _operatorStore,
        IJBProjects _projects,
        IJBDirectory _directory,
        IJBSplitsStore _splitsStore,
        IJBPrices _prices,
        IJBSingleTokenPaymentTerminalStore _store,
        IWETH _wETH,
        address _owner
    )
        JBPayoutRedemptionPaymentTerminal(
            JBTokens.ETH,
            18, // 18 decimals.
            JBCurrencies.ETH,
            _baseWeightCurrency,
            JBSplitsGroups.ETH_PAYOUT,
            _operatorStore,
            _projects,
            _directory,
            _splitsStore,
            _prices,
            _store,
            _owner
        )
    {
        wETH = _wETH;
    }

    //*********************************************************************//
    // ---------------------- internal transactions ---------------------- //
    //*********************************************************************//

    function _withdraw(Vault storage _vault, uint256 _assetAmount)
        internal
        virtual
        override
        nonReentrant()
        returns (uint256 sharesCost)
    {
        uint256 _balanceBefore = address(this).balance;
        // Withdraw exactly '_assetAmount' from vault
        sharesCost = _vault.impl.withdraw(
            _assetAmount,
            address(this),
            address(this)
        );
        // Convert wETH back into ETH
        wETH.withdraw(_assetAmount);
        // Sanity check, the increase in balance has to be exactly '_assetAmount'
        assert(_balanceBefore + _assetAmount == address(this).balance);
    }

    function _redeem(Vault storage _vault, uint256 _sharesAmount)
        internal
        virtual
        override
        nonReentrant()
        returns (uint256 assetsReceived)
    {
        uint256 _balanceBefore = address(this).balance;
        // Withdraw exactly '_assetAmount' from vault
        assetsReceived = _vault.impl.redeem(
            _sharesAmount,
            address(this),
            address(this)
        );
        // Convert wETH back into ETH
        wETH.withdraw(assetsReceived);
        // Sanity check, the increase in balance has to be exactly 'assetsReceived'
        assert(_balanceBefore + assetsReceived == address(this).balance);
    }

    function _deposit(Vault storage _vault, uint256 _assetAmount)
        internal
        virtual
        override
        nonReentrant()
        returns (uint256 sharesReceived)
    {
        // Convert ETH into wETH
        wETH.deposit{value: _assetAmount}();
        // Since multiple projects funds are here we can't give unlimited access to a specific vault
        wETH.approve(address(_vault.impl), _assetAmount);
        // Deposit into the vault
        sharesReceived = _vault.impl.deposit(_assetAmount, address(this));
    }

    /** 
    @notice
    Transfers tokens.

    ignored: _from The address from which the transfer should originate.
    @param _to The address to which the transfer should go.
    @param _amount The amount of the transfer, as a fixed point number with the same number of decimals as this terminal.
  */
    function _transferFrom(
        address,
        address payable _to,
        uint256 _amount
    ) internal override {
        Address.sendValue(_to, _amount);
    }

    /** 
    @notice
    Logic to be triggered before transferring tokens from this terminal.

    ignored: _to The address to which the transfer is going.
    ignored: _amount The amount of the transfer, as a fixed point number with the same number of decimals as this terminal.
  */
    // solhint-disable-next-line no-empty-blocks
    function _beforeTransferTo(address, uint256) internal override {}

    /**
    @notice
    Used when redeeming wETH for ETH
  */
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
