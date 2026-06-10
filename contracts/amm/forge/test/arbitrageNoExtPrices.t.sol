// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "amm/AMM_v1.sol";
import "amm/lib/ERC20.sol";

contract ArbitrageTest is Test {
    AMM public amm;
    ERC20 public t0;
    ERC20 public t1;

    address constant LP = address(0xABCD);
    address constant MANIP = address(0xBEEF);
    address constant ARBY = address(0xCAFE);

    function setUp() public {
        t0 = new ERC20(1_000_000 ether);
        t1 = new ERC20(1_000_000 ether);
        amm = new AMM(IERC20(address(t0)), IERC20(address(t1)));

        // Fund actors
        t0.transfer(LP, 10_000 ether);
        t1.transfer(LP, 10_000 ether);
        t0.transfer(MANIP, 10_000 ether);
        t1.transfer(MANIP, 10_000 ether);
        t0.transfer(ARBY, 10_000 ether);
        t1.transfer(ARBY, 10_000 ether);

        // Approvals
        vm.startPrank(LP);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(MANIP);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(ARBY);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        // Initial liquidity: symmetric 1000:1000 => price = 1e18
        vm.prank(LP);
        amm.deposit(1000 ether, 1000 ether);
    }

    function _valueInT1(address who) internal view returns (uint) {
        uint t1bal = t1.balanceOf(who);
        uint t0bal = t0.balanceOf(who);
        uint priceT0 = amm.price(address(t0)); // scaled by 1e18
        return t1bal + (t0bal * priceT0) / 1e18;
    }

    function test_Arbitrage_BuyLowSellHigh() public {
        // External price is 1 t1 per t0
        uint priceExt = 1e18;
        assertEq(amm.price(address(t0)), priceExt);

        // Manipulator pushes price of t0 down by swapping t0 -> t1
        vm.prank(MANIP);
        amm.swap(address(t0), 300 ether, 0);

        uint priceAfter = amm.price(address(t0));
        assertTrue(priceAfter < priceExt, "manipulation should lower t0 price");

        // Arbitrageur net value before (in t1-equivalent)
        uint netBefore = _valueInT1(ARBY);

        // Arbitrageur buys t0 from AMM (swap t1 -> t0) while t0 is cheap
        vm.prank(ARBY);
        amm.swap(address(t1), 500 ether, 0);

        // After swap, compute net value using external price (can sell t0 externally at priceExt)
        uint netAfter = _valueInT1(ARBY);

        // Expect profit (netAfter > netBefore)
        assertTrue(netAfter > netBefore, "arbitrageur should make positive profit");
    }
}
