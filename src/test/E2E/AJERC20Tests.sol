// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "./abstract/AJPayoutRedemptionTerminalTests.sol";
import {MockERC20} from "MockERC4626/MockERC20.sol";

contract AJERC20Tests is AJPayoutRedemptionTerminalTests {
    AJSingleVaultTerminalERC20 private _ajSingleVaultTerminalERC20;
    address private _ajERC20Asset;

    //*********************************************************************//
    // ------------------------- virtual methods ------------------------- //
    //*********************************************************************//

    function ajSingleVaultTerminal()
    internal
    view
    virtual
    override
    returns (IAJSingleVaultTerminal terminal){
        terminal = IAJSingleVaultTerminal(address(_ajSingleVaultTerminalERC20));
    }

    function ajTerminalAsset() internal virtual override view returns (address) {
        return _ajERC20Asset;
    }

    function ajVaultAsset() internal virtual override view returns (address) {
        return _ajERC20Asset;
    }

    function ajAssetMinter() internal virtual override view returns (IMintable) {
        return IMintable(_ajERC20Asset);
    }

    function ajAssetBalanceOf(address addr) internal virtual override view returns (uint256){
        return MockERC20(_ajERC20Asset).balanceOf(addr);
    }

    function fundWallet(address addr, uint256 amount) internal virtual override {
        IMintable(address(_ajERC20Asset)).mint(addr, amount);
    }

    function beforeTransfer(address from, address to, uint256 amount) internal virtual override returns (uint256 value) {
        evm.prank(from);
        MockERC20(_ajERC20Asset).approve(to, amount);
    }

    function setUp() public override {
        // Setup Juicebox
        super.setUp();

        // Create the valuable asset
        _ajERC20Asset = address(new MockERC20("MockAsset", "MAsset", 18));
        evm.label(_ajERC20Asset, "MockAsset");

        // Deploy AJ ERC20 Terminal
        _ajSingleVaultTerminalERC20 = new AJSingleVaultTerminalERC20(
            IERC20Metadata(_ajERC20Asset),
            jbLibraries().ETH(), // currency
            jbLibraries().ETH(), // base weight currency
            1, // JBSplitsGroup
            jbOperatorStore(),
            jbProjects(),
            jbDirectory(),
            jbSplitsStore(),
            jbPrices(),
            jbPaymentTerminalStore(),
            multisig()
        );

        // Label the ERC20 address
        evm.label(
            address(_ajSingleVaultTerminalERC20),
            "AJSingleVaultTerminalERC20"
        );
    }
}