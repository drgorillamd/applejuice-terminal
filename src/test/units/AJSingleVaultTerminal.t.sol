// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import 'jbx/interfaces/IJBPaymentTerminal.sol';
import 'jbx/interfaces/IJBRedemptionTerminal.sol';
import 'jbx/interfaces/IJBController.sol';
import 'jbx/abstract/JBOperatable.sol';
import 'jbx/libraries/JBOperations.sol';

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../../AJSingleVaultTerminalERC20.sol";
import 'forge-std/Test.sol';

contract TestUnitAJSingleVaultTerminal is Test {
    using stdStorage for StdStorage;

    IERC20Metadata mockToken;
    IJBOperatorStore mockOperatorStore;
    IJBProjects mockProjects;
    IJBDirectory mockDirectory;
    IJBSplitsStore mockSplitsStore;
    IJBPrices mockPrices;
    IJBSingleTokenPaymentTerminalStore mockSingleTerminalStore;
    IERC4626 mockVault;

    AJSingleVaultTerminalERC20 ajSingleVaultTerminal;

    // Except for decimals the other values are oddly specific on purpose so there are no mix ups
    uint256 decimals = 18;
    uint256 currency = 89185;
    uint256 baseWeightCurrency = 129258;
    uint256 payoutSplitsGroup = 192547;
    address terminalOwner;
    address projectOwner;
    address caller;
    address beneficiary;
    uint256 projectId = 420;

      function setUp() public {
        mockToken = IERC20Metadata(address(89));
        mockOperatorStore = IJBOperatorStore(address(10));
        mockProjects = IJBProjects(address(20));
        mockDirectory = IJBDirectory(address(30));
        mockSplitsStore = IJBSplitsStore(address(40));
        mockPrices = IJBPrices(address(50));
        mockSingleTerminalStore = IJBSingleTokenPaymentTerminalStore(address(60));
        mockVault = IERC4626(address(99));

        terminalOwner = address(59);
        projectOwner = address(69);
        caller = address(420);
        beneficiary = address(6942069);

        vm.etch(address(mockToken), new bytes(0x69));
        vm.etch(address(mockOperatorStore), new bytes(0x69));
        vm.etch(address(mockProjects), new bytes(0x69));
        vm.etch(address(mockDirectory), new bytes(0x69));
        vm.etch(address(mockSplitsStore), new bytes(0x69));
        vm.etch(address(mockPrices), new bytes(0x69));
        vm.etch(address(mockSingleTerminalStore), new bytes(0x69));
        vm.etch(address(mockVault), new bytes(0x69));

        vm.label(address(mockToken), 'mockToken');
        vm.label(address(mockOperatorStore), 'mockOperatorStore');
        vm.label(address(mockProjects), 'mockProjects');
        vm.label(address(mockDirectory), 'mockDirectory');
        vm.label(address(mockSplitsStore), 'mockSplitsStore');
        vm.label(address(mockPrices), 'mockPrices');
        vm.label(address(mockSingleTerminalStore), 'mockSingleTerminalStore');
        vm.label(address(mockVault), 'mockVault');
        vm.label(terminalOwner, 'terminalOwner');
        vm.label(projectOwner, 'projectOwner');
        vm.label(caller, 'caller');
        vm.label(beneficiary, 'beneficiary');

        // Mock token.decimals
        vm.mockCall(
            address(mockToken),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(decimals)
        );

        vm.mockCall(
            address(mockProjects),
            abi.encodeWithSelector(IERC721.ownerOf.selector, projectId),
            abi.encode(projectOwner)
        );
    }

    function testUnitTargetLocalBalanceDelta(uint40 _terminalBalancePPM, uint200 _terminalBalance, uint256 _vaultShares, uint256 _shareConversionRate, int128 _change) public {
        // Make sure the vaultShares and shareConversionRate are not so high that it overflows a uint256
        // if _shareConversionRate is 0 it can never overflow
        unchecked{
            if (_shareConversionRate != 0){
                vm.assume(_vaultShares * _shareConversionRate / _shareConversionRate == _vaultShares);
            }
        }

        // If _change is negative it has to be more than the totalWorth of the projects terminal
        // (you can't withdraw more than you have available)
        uint256 totalWorth = _terminalBalance + (_vaultShares * _shareConversionRate / 10**decimals);
        if(_change <= 0){
            // We increase it by 1, otherwise there is a chance that doing * -1 reverts
            _change++;
            vm.assume(-int256(totalWorth) < _change);
        }else{
            // Make sure the addition of totalWorth and _change won't overflow
            unchecked{
                uint256 total = totalWorth + uint128(_change);
                vm.assume(total >= totalWorth && total >= uint128(_change));
            }
        }

        // _terminalBalancePPM has to be in range 0 - 1_000_000 (0% - 100%)
        uint256 _terminalBalancePPMNormalised = _terminalBalancePPM / 1_000_000;
        vm.assume(_terminalBalancePPMNormalised <= 1_000_000);

        // Create terminal
         ajSingleVaultTerminal = new AJSingleVaultTerminalERC20(
            mockToken,
            currency,
            baseWeightCurrency,
            payoutSplitsGroup,
            mockOperatorStore,
            mockProjects,
            mockDirectory,
            mockSplitsStore,
            mockPrices,
            mockSingleTerminalStore,
            terminalOwner
        );
        vm.label(address(ajSingleVaultTerminal), 'AJSingleVaultTerminalERC20');

        // Set the storage directly
        _setVaultStorage(
            address(ajSingleVaultTerminal),
            projectId,
            address(mockVault),
            _terminalBalancePPMNormalised,
            _terminalBalance,
            _vaultShares
        );

         // Mock the vault conversionRate response
         vm.mockCall(
             address(mockVault),
             abi.encodeWithSelector(IERC4626.convertToAssets.selector, _vaultShares),
             abi.encode(_vaultShares * _shareConversionRate / 10**decimals)
         );

        if(_change >= 0){
            totalWorth += uint128(_change);
        }else{
            totalWorth -= uint128(_change * -1);
        }

        // Perform the calculations to check what it should be
        // Calculate what amount should be in the terminal
        uint256 targetBalance = totalWorth * _terminalBalancePPMNormalised / 1_000_000;
        // Calculate the difference between the amount in the terminal right now and what it should be
        int256 delta = int256(uint256(_terminalBalance)) + _change - int256(targetBalance);

        // Perform the call
        int256 _result = ajSingleVaultTerminal.targetLocalBalanceDelta(projectId, _change);

        assertEq(delta, _result);
    }



    function _setVaultStorage(address _terminal, uint256 _projectId, address _implementation, uint256 _localPPM, uint256 _localBalance, uint256 _shares) internal {
        // Set the implementation
        {
            // Get slot 1 because 0 errors for some reason
            uint slot = stdstore
                                .target(address(ajSingleVaultTerminal))
                                .sig(ajSingleVaultTerminal.projectVault.selector)
                                .with_key(uint256(_projectId))
                                .depth(1)
                                .find();

            // Use cheatcode to set slot 0
            vm.store(address(_terminal), bytes32(slot - 1), bytes32(uint256(uint160(_implementation))));
        }

        // Set the localPPM
        {
            stdstore
                .target(address(ajSingleVaultTerminal))
                .sig(ajSingleVaultTerminal.projectVault.selector)
                .with_key(uint256(_projectId))
                .depth(1).checked_write(_localPPM);
        }

        // Set the localBalance
        {
            stdstore
                .target(address(ajSingleVaultTerminal))
                .sig(ajSingleVaultTerminal.projectVault.selector)
                .with_key(uint256(_projectId))
                .depth(2).checked_write(_localBalance);
        }

        // Set the shares
        {
            stdstore
                .target(address(ajSingleVaultTerminal))
                .sig(ajSingleVaultTerminal.projectVault.selector)
                .with_key(uint256(_projectId))
                .depth(3).checked_write(_shares);
        }
    }
}