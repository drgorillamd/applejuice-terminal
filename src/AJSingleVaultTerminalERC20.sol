pragma solidity 0.8.6;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./abstract/AJSingleVaultTerminal.sol";
import "./interfaces/IWETH.sol";

contract AJSingleVaultTerminalERC20 is AJSingleVaultTerminal {
    /**
  @param _token The token that this terminal manages.
  @param _currency The currency that this terminal's token adheres to for price feeds.
  @param _baseWeightCurrency The currency to base token issuance on.
  @param _payoutSplitsGroup The group that denotes payout splits from this terminal in the splits store.
  @param _operatorStore A contract storing operator assignments.
  @param _projects A contract which mints ERC-721's that represent project ownership and transfers.
  @param _directory A contract storing directories of terminals and controllers for each project.
  @param _splitsStore A contract that stores splits for each project.
  @param _prices A contract that exposes price feeds.
  @param _store A contract that stores the terminal's data.
  @param _owner The address that will own this contract.
*/
    constructor(
        IERC20Metadata _token,
        uint256 _currency,
        uint256 _baseWeightCurrency,
        uint256 _payoutSplitsGroup,
        IJBOperatorStore _operatorStore,
        IJBProjects _projects,
        IJBDirectory _directory,
        IJBSplitsStore _splitsStore,
        IJBPrices _prices,
        IJBSingleTokenPaymentTerminalStore _store,
        address _owner
    )
        JBPayoutRedemptionPaymentTerminal(
            address(_token),
            _token.decimals(),
            _currency,
            _baseWeightCurrency,
            _payoutSplitsGroup,
            _operatorStore,
            _projects,
            _directory,
            _splitsStore,
            _prices,
            _store,
            _owner
        )
    {}

    //*********************************************************************//
    // ------------------------- internal methods ------------------------ //
    //*********************************************************************//

    function _withdraw(Vault storage _vault, uint256 _assetAmount)
        internal
        virtual
        override
        nonReentrant()
        returns (uint256 sharesCost)
    {
        uint256 _balanceBefore = IERC20(token).balanceOf(address(this));
        // Withdraw exactly '_assetAmount' from vault
        sharesCost = _vault.impl.withdraw(
            _assetAmount,
            address(this),
            address(this)
        );
        // Safety check so we don't update the accounting if the withdraw failed
        assert(IERC20(token).balanceOf(address(this)) == _balanceBefore + _assetAmount);
    }

    function _redeem(Vault storage _vault, uint256 _sharesAmount)
        internal
        virtual
        override
        nonReentrant()
        returns (uint256 assetsReceived)
    {
        uint256 _balanceBefore = IERC20(token).balanceOf(address(this));
        // Redeem exactly '_sharesAmount' from vault
        assetsReceived = _vault.impl.redeem(
            _sharesAmount,
            address(this),
            address(this)
        );
        // Safety check so we don't update the accounting if the withdraw failed
        assert(IERC20(token).balanceOf(address(this)) == _balanceBefore + assetsReceived);
    }

    function _deposit(Vault storage _vault, uint256 _assetAmount)
        internal
        virtual
        override
        nonReentrant()
        returns (uint256 sharesReceived)
    {
        // Since multiple projects funds are here we can't give unlimited access to a specific vault
        IERC20(token).approve(address(_vault.impl), _assetAmount);
        // Deposit into the vault
        sharesReceived = _vault.impl.deposit(_assetAmount, address(this));
    }

    /** 
    @notice
    Transfers tokens.

    @param _from The address from which the transfer should originate.
    @param _to The address to which the transfer should go.
    @param _amount The amount of the transfer, as a fixed point number with the same number of decimals as this terminal.
  */
    function _transferFrom(
        address _from,
        address payable _to,
        uint256 _amount
    ) internal override {
        _from == address(this)
            ? IERC20(token).transfer(_to, _amount)
            : IERC20(token).transferFrom(_from, _to, _amount);
    }

    /** 
    @notice
    Logic to be triggered before transferring tokens from this terminal.

    @param _to The address to which the transfer is going.
    @param _amount The amount of the transfer, as a fixed point number with the same number of decimals as this terminal.
  */
    function _beforeTransferTo(address _to, uint256 _amount) internal override {
        IERC20(token).approve(_to, _amount);
    }
}
