pragma solidity 0.8.6;

import "../interfaces/IERC4626.sol";
import "../interfaces/ILido.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 @notice
 AppleJuice terminal ERC4626 strategy: Lido stETH
*/

contract LidoJuice is IERC4626, ERC20 {
    error LidoJuice_zeroEth();
    error LidoJuice_wrongStETHReceived();
    error LidoJuice_insufficientEthReceived();

    ILido stETH;

    constructor(ILido _stETH) ERC20("LidoJuice", "AstETH") {
        stETH = _stETH;
    }

    /// @notice The address of the underlying ERC20 token used for
    /// the Vault for accounting, depositing, and withdrawing.
    function asset() external view override returns (address asset) {
        return address(this);
    }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets()
        external
        view
        override
        returns (uint256 totalAssets)
    {
        return stETH.balanceOf(address(this));
    }

    /*////////////////////////////////////////////////////////
                      Deposit/Withdrawal Logic
    ////////////////////////////////////////////////////////*/

    /// @notice Mints `shares` Vault shares to `receiver` by
    /// depositing exactly `assets` of underlying tokens.
    function deposit(uint256 assets, address receiver)
        external
        payable
        override
        returns (uint256 shares)
    {
        if (msg.value == 0) revert LidoJuice_zeroEth();

        // Compute share of the asset managed by this vault
        shares = (msg.value * totalSupply()) / stETH.balanceOf(address(this));

        // TODO:Mint to external senders allowed? Or send to AppleJuiceTerminal only (and revert for other callers then)
        _mint(msg.sender, shares);

        // Stake
        uint256 _received = stETH.submit{value: msg.value}(address(this));

        // Should be 1:1
        if (_received != msg.value) revert LidoJuice_wrongStETHReceived();
    }

    /// @notice Mints exactly `shares` Vault shares to `receiver`
    /// by depositing `assets` of underlying tokens.
    function mint(uint256 shares, address receiver)
        external
        payable
        override
        returns (uint256 assets)
    {
        // Compute the eth value of the share amount wanted
        uint256 _ethInNeeded = (shares * stETH.balanceOf(address(this))) /
            totalSupply();

        if (msg.value < _ethInNeeded)
            revert LidoJuice_insufficientEthReceived();

        _mint(shares, msg.sender);

        uint256 _received = stETH.submit{value: msg.value}(address(this));
        if (_received != _ethInNeeded) revert LidoJuice_wrongStETHReceived();

        // Reimburse extra eth sent
        payable(msg.sender).call{value: msg.value - _ethInNeeded}("");
    }

    /// @notice Redeems `shares` from `owner` and sends `assets`
    /// of underlying tokens to `receiver`.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external override returns (uint256 shares) {}

    /// @notice Redeems `shares` from `owner` and sends `assets`
    /// of underlying tokens to `receiver`.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external override returns (uint256 assets) {}

    /*////////////////////////////////////////////////////////
                      Vault Accounting Logic
    ////////////////////////////////////////////////////////*/

    /// @notice The amount of shares that the vault would
    /// exchange for the amount of assets provided, in an
    /// ideal scenario where all the conditions are met.
    function convertToShares(uint256 assets)
        external
        view
        override
        returns (uint256 shares)
    {}

    /// @notice The amount of assets that the vault would
    /// exchange for the amount of shares provided, in an
    /// ideal scenario where all the conditions are met.
    function convertToAssets(uint256 shares)
        external
        view
        override
        returns (uint256 assets)
    {}

    /// @notice Total number of underlying assets that can
    /// be deposited by `owner` into the Vault, where `owner`
    /// corresponds to the input parameter `receiver` of a
    /// `deposit` call.
    function maxDeposit(address owner)
        external
        view
        override
        returns (uint256 maxAssets)
    {}

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their deposit at the current block, given
    /// current on-chain conditions.
    function previewDeposit(uint256 assets)
        external
        view
        override
        returns (uint256 shares)
    {}

    /// @notice Total number of underlying shares that can be minted
    /// for `owner`, where `owner` corresponds to the input
    /// parameter `receiver` of a `mint` call.
    function maxMint(address owner)
        external
        view
        override
        returns (uint256 maxShares)
    {}

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their mint at the current block, given
    /// current on-chain conditions.
    function previewMint(uint256 shares)
        external
        view
        override
        returns (uint256 assets)
    {}

    /// @notice Total number of underlying assets that can be
    /// withdrawn from the Vault by `owner`, where `owner`
    /// corresponds to the input parameter of a `withdraw` call.
    function maxWithdraw(address owner)
        external
        view
        override
        returns (uint256 maxAssets)
    {}

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their withdrawal at the current block,
    /// given current on-chain conditions.
    function previewWithdraw(uint256 assets)
        external
        view
        override
        returns (uint256 shares)
    {}

    /// @notice Total number of underlying shares that can be
    /// redeemed from the Vault by `owner`, where `owner` corresponds
    /// to the input parameter of a `redeem` call.
    function maxRedeem(address owner)
        external
        view
        override
        returns (uint256 maxShares)
    {}

    /// @notice Allows an on-chain or off-chain user to simulate
    /// the effects of their redeemption at the current block,
    /// given current on-chain conditions.
    function previewRedeem(uint256 shares)
        external
        view
        override
        returns (uint256 assets)
    {}
}
