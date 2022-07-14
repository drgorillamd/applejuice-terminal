// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "./abstract/AJPayoutRedemptionTerminalTests.sol";
import {MockERC20} from "MockERC4626/MockERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import "../../AJSingleVaultTerminalETH.sol";
import "./helpers/WETHMinter.sol";


contract AJETHTests is AJPayoutRedemptionTerminalTests {
    AJSingleVaultTerminalETH private _ajSingleVaultTerminalETH;
    IWETH private _weth;
    IMintable private _minter;

    //*********************************************************************//
    // ---------------------------  overrides ---------------------------- //
    //*********************************************************************//

    function ajSingleVaultTerminal()
    internal
    view
    virtual
    override
    returns (IAJSingleVaultTerminal terminal){
        terminal = IAJSingleVaultTerminal(address(_ajSingleVaultTerminalETH));
    }

    function ajTerminalAsset() internal virtual override view returns (address) {
        return JBTokens.ETH;
    }

    function ajVaultAsset() internal virtual override view returns (address) {
        return address(_weth);
    }

    function ajAssetMinter() internal virtual override view returns (IMintable) {
        return _minter;
    }

    function ajAssetBalanceOf(address addr) internal virtual override view returns (uint256){
        return payable(addr).balance + _weth.balanceOf(addr);
    }

    function fundWallet(address addr, uint256 amount) internal virtual override {
        evm.deal(addr, payable(addr).balance + amount);
    }

    function beforeTransfer(address from, address to, uint256 amount) internal virtual override returns (uint256) {
        return amount;
    }

    //*********************************************************************//
    // ------------------------- virtual methods ------------------------- //
    //*********************************************************************//

    function setUp() public override {
        // Setup Juicebox
        super.setUp();

        // Create the wETH
        _weth = IWETH(payable(address(new WETH())));
        evm.label(address(_weth), "wETH");

        // Create the wETH minter
        _minter = new WETHMinter(_weth);

        // Deploy AJ ERC20 Terminal
        _ajSingleVaultTerminalETH = new AJSingleVaultTerminalETH(
            jbLibraries().ETH(), // base weight currency
            jbOperatorStore(),
            jbProjects(),
            jbDirectory(),
            jbSplitsStore(),
            jbPrices(),
            jbPaymentTerminalStore(),
            _weth,
            multisig()
        );

        // Label the ERC20 address
        evm.label(
            address(_ajSingleVaultTerminalETH),
            "AJSingleVaultTerminalETH"
        );
    }
}