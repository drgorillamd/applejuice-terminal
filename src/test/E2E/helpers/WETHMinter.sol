pragma solidity 0.8.6;

import "forge-std/Vm.sol";

import {IMintable} from "MockERC4626/interfaces/IMintable.sol";
import "../../../interfaces/IWETH.sol";

contract WETHMinter is IMintable {
    IWETH private weth;
    Vm private evm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    constructor(IWETH _weth){
        weth = _weth;
    }

    function mint(address _to, uint256 _amount) external override {
        // Deal this contract the needed ETH
        evm.deal(address(this), _amount);
        // Wrap the ETH into wETH
        weth.deposit{value: _amount}();
        // Transfer the wETH to the address that needs it
        weth.transfer(_to, _amount);
    }
}