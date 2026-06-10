// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
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

        // set external oracle prices (scaled by 1e18)
        setOraclePrices(1e18, 1e18);

        // print initial state
        print_state("setup");
    }

    // --- Test-level oracle (completely independent from AMM state) ---
    uint public extPriceT0; // price of t0 in base currency, scaled 1e18
    uint public extPriceT1; // price of t1 in base currency, scaled 1e18

    function setOraclePrices(uint p0, uint p1) internal {
        extPriceT0 = p0;
        extPriceT1 = p1;
    }

    function oraclePrice(address token) internal view returns (uint) {
        if (token == address(t0)) return extPriceT0;
        if (token == address(t1)) return extPriceT1;
        revert("invalid token");
    }

    /// @notice Wealth of `who` in base currency units (price scaled by 1e18)
    function wealth(address who) internal view returns (uint) {
        uint b0 = t0.balanceOf(who);
        uint b1 = t1.balanceOf(who);
        return (b0 * extPriceT0 + b1 * extPriceT1) / 1e18;
    }

    /// @dev Print useful state about the AMM and actors to the console
    function print_state(string memory tag) internal view {
        console.log("--- %s ---", tag);
        console.log("AMM r0:", amm.r0());
        console.log("AMM r1:", amm.r1());
        console.log("AMM supply:", amm.supply());
        // AMM internal price (scaled 1e18)
        console.log("AMM price t0 (t1 per t0 *1e18):", amm.price(address(t0)));
        // external oracle prices
        console.log("Oracle price t0:", extPriceT0);
        console.log("Oracle price t1:", extPriceT1);

        // Balances
        console.log("LP balances t0:", t0.balanceOf(LP));
        console.log("LP balances t1:", t1.balanceOf(LP));
        console.log("MANIP balances t0:", t0.balanceOf(MANIP));
        console.log("MANIP balances t1:", t1.balanceOf(MANIP));
        console.log("ARBY balances t0:", t0.balanceOf(ARBY));
        console.log("ARBY balances t1:", t1.balanceOf(ARBY));

        // Wealth using external oracle
        console.log("WEALTH ARBY:", wealth(ARBY));

        // minted LP tokens
        console.log("minted LP:", amm.minted(LP));
        console.log("minted MANIP:", amm.minted(MANIP));
        console.log("minted ARBY:", amm.minted(ARBY));
        console.log("--------------------");
    }

    function test_Arbitrage_BuyLowSellHigh() public {
        // External price is 1 t1 per t0
        uint priceExt = 1e18;
        assertEq(amm.price(address(t0)), priceExt);

        // print AMM before manipulation
        print_state("before manipulation");

        // Manipulator pushes price of t0 down by swapping t0 -> t1
        vm.prank(MANIP);
        amm.swap(address(t0), 300 ether, 0);

        uint priceAfter = amm.price(address(t0));
        assertTrue(priceAfter < priceExt, "manipulation should lower t0 price");

        // print state after manipulation
        print_state("after manipulation");

        // Arbitrageur net value before (using external oracle prices)
        uint netBefore = wealth(ARBY);
        console.log("netBefore:", netBefore);

        // print state right before arbitrage
        print_state("pre-arbitrage");

        // Arbitrageur buys t0 from AMM (swap t1 -> t0) while t0 is cheap
        vm.prank(ARBY);
        amm.swap(address(t1), 500 ether, 0);

        // After swap, compute net value using external oracle prices
        uint netAfter = wealth(ARBY);
        console.log("netAfter:", netAfter);

        // print state after arbitrage
        print_state("post-arbitrage");

        // Expect profit (netAfter > netBefore)
        assertTrue(netAfter > netBefore, "arbitrageur should make positive profit");
    }
}
