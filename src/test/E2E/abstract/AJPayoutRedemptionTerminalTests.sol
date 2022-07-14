// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "../../../AJSingleVaultTerminalERC20.sol";
import "jbx/system_tests/helpers/TestBaseWorkflow.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IMintable} from "MockERC4626/interfaces/IMintable.sol";
import {MockLinearGainsERC4626} from "MockERC4626/vaults/MockLinearGainsERC4626.sol";
import {MockERC20} from "MockERC4626/MockERC20.sol";
import "../../../interfaces/IAJSingleVaultTerminal.sol";

abstract contract AJPayoutRedemptionTerminalTests is TestBaseWorkflow {
    JBController controller;
    JBProjectMetadata _projectMetadata;
    JBFundingCycleData _data;
    JBFundingCycleMetadata _metadata;
    JBGroupedSplits[] _groupedSplits; // Default empty
    JBFundAccessConstraints[] _fundAccessConstraints; // Default empty

    //*********************************************************************//
    // ------------------------- virtual methods ------------------------- //
    //*********************************************************************//

    function ajSingleVaultTerminal()
    internal
    virtual
    view
    returns (IAJSingleVaultTerminal terminal);

    function ajTerminalAsset() internal virtual view returns (address);

    function ajVaultAsset() internal virtual view returns (address);

    function ajAssetMinter() internal virtual view returns (IMintable);

    function ajAssetBalanceOf(address addr) internal virtual view returns (uint256);

    function fundWallet(address addr, uint256 amount) internal virtual;

    function beforeTransfer(address from, address to, uint256 amount) internal virtual returns (uint256 value);

    //*********************************************************************//
    // ------------------------- internal views -------------------------- //
    //*********************************************************************//

    function setUp() public virtual override {
        super.setUp();

        controller = jbController();

        _projectMetadata = JBProjectMetadata({
            content: "myIPFSHash",
            domain: 1
        });

        _data = JBFundingCycleData({
            duration: 14,
            weight: 1000 * 10**18,
            discountRate: 450000000,
            ballot: IJBFundingCycleBallot(address(0))
        });

        _metadata = JBFundingCycleMetadata({
            global: JBGlobalFundingCycleMetadata({
                allowSetTerminals: false,
                allowSetController: false
            }),
            reservedRate: 5000, //50%
            redemptionRate: 5000, //50%
            ballotRedemptionRate: 0,
            pausePay: false,
            pauseDistributions: false,
            pauseRedeem: false,
            pauseBurn: false,
            allowMinting: false,
            allowChangeToken: false,
            allowTerminalMigration: false,
            allowControllerMigration: false,
            holdFees: false,
            useTotalOverflowForRedemptions: false,
            useDataSourceForPay: false,
            useDataSourceForRedeem: false,
            dataSource: address(0)
        });
    }

    function testPayRedeem() public {
        testPayRedeemFuzz(100_000 * 1_000_000, 5 ether, 1, 1 weeks);
    }

    function testPayRedeemFuzz(uint40 _LocalBalancePPM, uint128 _payAmount, uint256 _redeemAmount, uint32 _secondsBetweenPayAndRedeem) public {
        uint256 _localBalancePPMNormalised = _LocalBalancePPM / 1_000_000;
        evm.assume(_localBalancePPMNormalised > 0 && _localBalancePPMNormalised <= 1_000_000);
        evm.assume(_payAmount > 0);
        evm.assume(_redeemAmount > 0);

        IAJSingleVaultTerminal _ajSingleVaultTerminal = ajSingleVaultTerminal();

        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = _ajSingleVaultTerminal;

        // Configure project
        uint256 projectId = controller.launchProjectFor(
            msg.sender,
            _projectMetadata,
            _data,
            _metadata,
            block.timestamp,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        // Create the ERC4626 Vault
        MockLinearGainsERC4626 vault = new MockLinearGainsERC4626(
            ajVaultAsset(),
            ajAssetMinter(),
            "yJBX",
            "yJBX",
            1000
        );

        // Configure the AJ terminal to use the MockERC4626
        evm.prank(msg.sender);
        _ajSingleVaultTerminal.setVault(
            projectId,
            IERC4626(address(vault)),
            VaultConfig(_localBalancePPMNormalised),
            0
        );

        // Mint some tokens the payer can use
        address payer = address(0xf00);

        // Mint and Approve the tokens to be paid (if needed)
        fundWallet(payer, _payAmount);
        uint256 _value = beforeTransfer(payer, address(_ajSingleVaultTerminal), _payAmount);

        // Perform the pay
        evm.startPrank(payer);
        uint256 jbTokensReceived = _ajSingleVaultTerminal.pay{value: _value}(
            projectId,
            _payAmount,
            ajVaultAsset(),
            payer,
            0,
            false,
            '',
            ''
        );

        // Check that: Balance in the terminal is correct, balance in the vault is correct
        uint256 _expectedBalanceInVault = _payAmount * _localBalancePPMNormalised / 1_000_000;
        assertEq(ajAssetBalanceOf(address(_ajSingleVaultTerminal)), _expectedBalanceInVault);
        assertEq(ajAssetBalanceOf(address(vault)), _payAmount - _expectedBalanceInVault);

        // Fast forward time (assumes 15 second blocks)
        evm.warp(block.timestamp + _secondsBetweenPayAndRedeem);
        evm.roll(block.number + _secondsBetweenPayAndRedeem / 15);

        // Check the store to see what overflow we should be expecting
        uint256 overflowExpected = jbPaymentTerminalStore().currentReclaimableOverflowOf(
            IJBSingleTokenPaymentTerminal(address(_ajSingleVaultTerminal)),
            projectId,
            jbTokensReceived,
            false
        );
        uint256 _userBalanceBeforeWithdraw = ajAssetBalanceOf(payer);

        // Perform the redeem
        _ajSingleVaultTerminal.redeemTokensOf(payer, projectId, jbTokensReceived, address(jbToken()), 0, payable(payer), '', '');
        evm.stopPrank();

        // If the initial pay amount was more than 10 wei there should be some overflow
        if(_payAmount > 10){
            assertGt(overflowExpected, 0);
        }

        // Check that the user received the expected amount
        assertEq(ajAssetBalanceOf(payer), _userBalanceBeforeWithdraw + overflowExpected);
    }

    function testAllowance() public {
        testAllowanceFuzz(100_000 * 1_000_000, 10 ether, 5 ether, 20 ether, 2 weeks);
    }

    /**
        @notice Adapted version of 'TestERC20Terminal.testAllowanceERC20' for AJ single vaults
    */
    function testAllowanceFuzz(uint40 _LocalBalancePPM, uint232 _allowance, uint232 _target, uint96 _balance, uint32 _secondsBetweenActions) public {
        uint256 _localBalancePPMNormalised = _LocalBalancePPM / 1_000_000;
        evm.assume(_localBalancePPMNormalised > 0 && _localBalancePPMNormalised <= 1_000_000);

        IAJSingleVaultTerminal _ajSingleVaultTerminal = ajSingleVaultTerminal();

        IJBPaymentTerminal[] memory _terminals = new IJBPaymentTerminal[](1);
        _terminals[0] = _ajSingleVaultTerminal;

        _fundAccessConstraints.push(
            JBFundAccessConstraints({
                terminal: _ajSingleVaultTerminal,
                token: ajTerminalAsset(),
                distributionLimit: _target,
                overflowAllowance: _allowance,
                distributionLimitCurrency: jbLibraries().ETH(),
                overflowAllowanceCurrency: jbLibraries().ETH()
            })
        );

        // Configure project
        address _projectOwner = address(420);
        uint256 projectId = controller.launchProjectFor(
            _projectOwner,
            _projectMetadata,
            _data,
            _metadata,
            block.timestamp,
            _groupedSplits,
            _fundAccessConstraints,
            _terminals,
            ""
        );

        // Scoped to prevent stack too deep
        {
            // Create the ERC4626 Vault
            MockLinearGainsERC4626 vault = new MockLinearGainsERC4626(
                ajVaultAsset(),
                ajAssetMinter(),
                "yJBX",
                "yJBX",
                1000
            );

            evm.prank(_projectOwner);
            _ajSingleVaultTerminal.setVault(
                projectId,
                IERC4626(address(vault)),
                VaultConfig(_localBalancePPMNormalised),
                0
            );
        }

        // Mint some tokens the payer can use
        address payer = address(0xf00);

        // Mint and Approve the tokens to be paid (if needed)
        fundWallet(payer, _balance);
        uint256 _value = beforeTransfer(payer, address(_ajSingleVaultTerminal), _balance);

        // Perform the pay
        evm.prank(payer);
        uint256 jbTokensReceived = _ajSingleVaultTerminal.pay{value: _value}(
            projectId,
            _balance,
            ajVaultAsset(),
            payer,
            0,
            false,
            '',
            ''
        );

        // Fast forward time (assumes 15 second blocks)
        evm.warp(block.timestamp + _secondsBetweenActions);
        evm.roll(block.number + _secondsBetweenActions / 15);

        // Discretionary use of overflow allowance by project owner (allowance = 5ETH)
        bool willRevert;
        if (_allowance == 0) {
            evm.expectRevert(abi.encodeWithSignature('INADEQUATE_CONTROLLER_ALLOWANCE()'));
            willRevert = true;
        } else if (_target >= _balance || _allowance > (_balance - _target)) {
            // Too much to withdraw or no overflow ?
            evm.expectRevert(abi.encodeWithSignature('INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()'));
            willRevert = true;
        }else if(_allowance > ajAssetBalanceOf(address(_ajSingleVaultTerminal))){
            // If the amount being withdrawn as allowance is more than the terminal has in its localBalance
            // than the terminal will withdraw from the vault
            evm.expectEmit(true, true, true, false);
            emit Withdraw(address(_ajSingleVaultTerminal), address(_ajSingleVaultTerminal), address(_ajSingleVaultTerminal), 0, 0);
        }

        evm.prank(_projectOwner);
        _ajSingleVaultTerminal.useAllowanceOf(
            projectId,
            _allowance,
            1, // Currency
            address(0), //token (unused)
            0, // Min wei out
            payable(_projectOwner), // Beneficiary
            'MEMO'
        );

        // Fast forward time (assumes 15 second blocks)
        evm.warp(block.timestamp + _secondsBetweenActions);
        evm.roll(block.number + _secondsBetweenActions / 15);

        if (_balance != 0 && !willRevert)
            assertEq(
                ajAssetBalanceOf(_projectOwner),
                PRBMath.mulDiv(_allowance, jbLibraries().MAX_FEE(), jbLibraries().MAX_FEE() + _ajSingleVaultTerminal.fee())
            );

        // Distribute the funding target ETH -> no split then beneficiary is the project owner
        uint256 initBalance = ajAssetBalanceOf(_projectOwner);

        if (_target > _balance){
            evm.expectRevert(abi.encodeWithSignature('INADEQUATE_PAYMENT_TERMINAL_STORE_BALANCE()'));
        } else if (_target == 0){
            evm.expectRevert(abi.encodeWithSignature('DISTRIBUTION_AMOUNT_LIMIT_REACHED()'));
        } else if(_target > ajAssetBalanceOf(address(_ajSingleVaultTerminal))){
            // If the amount being withdrawn as allowance is more than the terminal has in its localBalance
            // than the terminal will withdraw from the vault
            evm.expectEmit(true, true, true, false);
            emit Withdraw(address(_ajSingleVaultTerminal), address(_ajSingleVaultTerminal), address(_ajSingleVaultTerminal), 0, 0);
        }

        evm.prank(_projectOwner);
        _ajSingleVaultTerminal.distributePayoutsOf(
            projectId,
            _target,
            1, // Currency
            address(0), //token (unused)
            0, // Min wei out
            'Foundry payment' // Memo
        );

        // Funds leaving the ecosystem -> fee taken
        if (_target <= _balance && _target != 0)
            assertEq(
                ajAssetBalanceOf(_projectOwner),
                initBalance +
                PRBMath.mulDiv(_target, jbLibraries().MAX_FEE(), _ajSingleVaultTerminal.fee() + jbLibraries().MAX_FEE())
            );

        // redeem eth from the overflow by the token holder:
        uint256 senderBalance = jbTokenStore().balanceOf(payer, projectId);

        evm.prank(payer);
        _ajSingleVaultTerminal.redeemTokensOf(
            payer,
            projectId,
            senderBalance,
            address(0), //token (unused)
            0,
            payable(payer),
            'gimme my token back',
            new bytes(0)
        );

        // verify: beneficiary should have a balance of 0 JBTokens
        assertEq(jbTokenStore().balanceOf(payer, projectId), 0);
    }

    // Vault events
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
}
