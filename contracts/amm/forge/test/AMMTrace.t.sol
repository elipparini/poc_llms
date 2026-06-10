// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "amm/AMM_v1.sol";
import "amm/lib/ERC20.sol";

/**
 * @title AMMTrace
 * @notice 10 trace-based tests that exercise the AMM through sequences of
 *         deposit / swap / redeem transactions (5–20 txs each).
 *         Invariants checked after each step:
 *           - token balances of the AMM contract equal r0 / r1
 *           - constant-product k = r0*r1 never decreases after a swap
 *           - supply and per-user minted accounting stay consistent
 */
contract AMMTraceTest is Test {
    AMM    public amm;
    ERC20  public t0;
    ERC20  public t1;

    address constant ALICE = address(0xA11CE);
    address constant BOB   = address(0xB0B);
    address constant CAROL = address(0xCACA0);

    uint constant SUPPLY = 10_000_000 ether;

    // ────────────────────────── setup ──────────────────────────────────────

    function setUp() public {
        t0  = new ERC20(SUPPLY);
        t1  = new ERC20(SUPPLY);
        amm = new AMM(IERC20(address(t0)), IERC20(address(t1)));

        // Distribute tokens to test users
        t0.transfer(ALICE, 1_000_000 ether);
        t1.transfer(ALICE, 1_000_000 ether);
        t0.transfer(BOB,   1_000_000 ether);
        t1.transfer(BOB,   1_000_000 ether);
        t0.transfer(CAROL, 1_000_000 ether);
        t1.transfer(CAROL, 1_000_000 ether);

        // Infinite approvals for all users
        vm.startPrank(ALICE);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(BOB);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(CAROL);
        t0.approve(address(amm), type(uint256).max);
        t1.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    // ────────────────────────── helpers ────────────────────────────────────

    /// @dev Expected swap output for token_in → token_out (no fees).
    function _expectedOut(uint x_in, uint r_in, uint r_out) internal pure returns (uint) {
        return (x_in * r_out) / (r_in + x_in);
    }

    /// @dev Assert that the AMM's on-chain token balances equal its stored reserves.
    function _assertBalancesMatchReserves() internal view {
        assertEq(t0.balanceOf(address(amm)), amm.r0(), "r0 mismatch");
        assertEq(t1.balanceOf(address(amm)), amm.r1(), "r1 mismatch");
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 1 – single user: deposit → 3 swaps → partial redeem  (7 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace1_DepositSwapRedeem() public {
        // Tx 1: Alice deposits initial liquidity 1:2 ratio
        vm.prank(ALICE);
        amm.deposit(1000 ether, 2000 ether);
        assertEq(amm.r0(), 1000 ether);
        assertEq(amm.r1(), 2000 ether);
        assertEq(amm.supply(), 1000 ether);
        assertEq(amm.minted(ALICE), 1000 ether);
        _assertBalancesMatchReserves();

        // Tx 2: Alice swaps 100 t0 → t1
        uint k = amm.r0() * amm.r1();
        vm.prank(ALICE);
        amm.swap(address(t0), 100 ether, 0);
        assertGe(amm.r0() * amm.r1(), k, "k decreased after swap");
        _assertBalancesMatchReserves();

        // Tx 3: Alice swaps 50 t0 → t1
        k = amm.r0() * amm.r1();
        vm.prank(ALICE);
        amm.swap(address(t0), 50 ether, 0);
        assertGe(amm.r0() * amm.r1(), k, "k decreased after swap");
        _assertBalancesMatchReserves();

        // Tx 4: Alice swaps 200 t1 → t0
        k = amm.r0() * amm.r1();
        vm.prank(ALICE);
        amm.swap(address(t1), 200 ether, 0);
        assertGe(amm.r0() * amm.r1(), k, "k decreased after swap");
        _assertBalancesMatchReserves();

        // Tx 5: Alice redeems half her shares
        uint halfShares = amm.minted(ALICE) / 2;
        uint supplyBefore = amm.supply();
        vm.prank(ALICE);
        amm.redeem(halfShares);
        assertEq(amm.supply(), supplyBefore - halfShares, "supply accounting");
        assertEq(amm.minted(ALICE), supplyBefore - halfShares, "minted accounting");
        _assertBalancesMatchReserves();

        // Tx 6-7: Alice redeems half the remaining shares twice
        uint shares = amm.minted(ALICE) / 2;
        vm.prank(ALICE);
        amm.redeem(shares);
        _assertBalancesMatchReserves();

        shares = amm.minted(ALICE) / 2;
        vm.prank(ALICE);
        amm.redeem(shares);
        _assertBalancesMatchReserves();
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 2 – two depositors, single swap, both redeem  (10 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace2_TwoDepositors() public {
        // Tx 1: Alice deposits 2000:4000
        vm.prank(ALICE);
        amm.deposit(2000 ether, 4000 ether);
        uint aliceShares = amm.minted(ALICE);
        assertEq(aliceShares, 2000 ether);

        // Tx 2: Bob deposits proportionally 1000:2000 (same ratio)
        vm.prank(BOB);
        amm.deposit(1000 ether, 2000 ether);
        uint bobShares = amm.minted(BOB);
        assertEq(amm.supply(), aliceShares + bobShares, "supply = sum of minted");
        _assertBalancesMatchReserves();

        // Tx 3-5: three swaps
        for (uint i = 0; i < 3; i++) {
            uint k = amm.r0() * amm.r1();
            vm.prank(ALICE);
            amm.swap(address(t0), 100 ether, 0);
            assertGe(amm.r0() * amm.r1(), k);
            _assertBalancesMatchReserves();
        }

        // Tx 6: Bob redeems his shares (supply > bobShares because Alice still has hers)
        uint bobShares2 = amm.minted(BOB);
        vm.prank(BOB);
        amm.redeem(bobShares2);
        assertEq(amm.minted(BOB), 0);
        _assertBalancesMatchReserves();

        // Tx 7-10: Alice progressively redeems in 4 chunks
        for (uint i = 0; i < 4; i++) {
            uint chunk = amm.minted(ALICE) / 2;
            if (chunk == 0) break;
            vm.prank(ALICE);
            amm.redeem(chunk);
            _assertBalancesMatchReserves();
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 3 – alternating swaps t0→t1 and t1→t0  (9 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace3_AlternatingSwaps() public {
        // Tx 1: Alice deposits
        vm.prank(ALICE);
        amm.deposit(5000 ether, 5000 ether);
        _assertBalancesMatchReserves();

        // Tx 2-7: alternating swaps
        address[6] memory tokens = [
            address(t0), address(t1),
            address(t0), address(t1),
            address(t0), address(t1)
        ];
        uint[6] memory amounts = [
            uint(200 ether), uint(150 ether),
            uint(300 ether), uint(250 ether),
            uint(100 ether), uint(400 ether)
        ];
        for (uint i = 0; i < 6; i++) {
            uint k = amm.r0() * amm.r1();
            vm.prank(ALICE);
            amm.swap(tokens[i], amounts[i], 0);
            assertGe(amm.r0() * amm.r1(), k, "k decreased");
            _assertBalancesMatchReserves();
        }

        // Tx 8: partial redeem
        uint shares = amm.minted(ALICE) / 3;
        vm.prank(ALICE);
        amm.redeem(shares);
        _assertBalancesMatchReserves();

        // Tx 9: another partial redeem
        shares = amm.minted(ALICE) / 3;
        vm.prank(ALICE);
        amm.redeem(shares);
        _assertBalancesMatchReserves();
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 4 – many small swaps in the same direction  (12 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace4_ManySmallSwaps() public {
        // Tx 1: deposit
        vm.prank(ALICE);
        amm.deposit(10000 ether, 10000 ether);
        uint kInit = amm.r0() * amm.r1();

        // Tx 2-11: 10 small swaps t0 → t1
        for (uint i = 0; i < 10; i++) {
            uint k = amm.r0() * amm.r1();
            vm.prank(BOB);
            amm.swap(address(t0), 50 ether, 0);
            assertGe(amm.r0() * amm.r1(), k);
            _assertBalancesMatchReserves();
        }

        // Product should have grown (or stayed same due to rounding)
        assertGe(amm.r0() * amm.r1(), kInit);

        // Tx 12: Alice redeems a portion
        uint shares = amm.minted(ALICE) / 4;
        vm.prank(ALICE);
        amm.redeem(shares);
        _assertBalancesMatchReserves();
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 5 – three depositors, multiple swaps, all redeem  (16 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace5_ThreeDepositors() public {
        // Tx 1: Alice seeds the pool 3:6
        vm.prank(ALICE);
        amm.deposit(3000 ether, 6000 ether);
        uint aliceShares = amm.minted(ALICE);

        // Tx 2: Bob deposits same ratio 1500:3000
        vm.prank(BOB);
        amm.deposit(1500 ether, 3000 ether);
        uint bobShares = amm.minted(BOB);

        // Tx 3: Carol deposits same ratio 750:1500
        vm.prank(CAROL);
        amm.deposit(750 ether, 1500 ether);
        uint carolShares = amm.minted(CAROL);

        assertEq(amm.supply(), aliceShares + bobShares + carolShares);
        _assertBalancesMatchReserves();

        // Tx 4-8: five swaps by different users
        vm.prank(ALICE); amm.swap(address(t0), 100 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(BOB);   amm.swap(address(t1), 200 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(CAROL); amm.swap(address(t0), 150 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(ALICE); amm.swap(address(t1), 300 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(BOB);   amm.swap(address(t0), 80 ether, 0);
        _assertBalancesMatchReserves();

        // Tx 9: Carol redeems all (supply still > carolShares)
        vm.prank(CAROL);
        amm.redeem(carolShares);
        assertEq(amm.minted(CAROL), 0);
        _assertBalancesMatchReserves();

        // Tx 10-13: Bob redeems in 2 steps
        // Pre-compute minted before vm.prank to avoid prank-consumption by the staticcall.
        uint bobHalf = amm.minted(BOB) / 2;
        vm.prank(BOB);
        amm.redeem(bobHalf);
        _assertBalancesMatchReserves();

        uint bobRemaining = amm.minted(BOB) / 2;
        vm.prank(BOB);
        amm.redeem(bobRemaining);
        _assertBalancesMatchReserves();

        // Tx 14-16: Alice redeems in 3 steps
        for (uint i = 0; i < 3; i++) {
            uint chunk = amm.minted(ALICE) / 2;
            if (chunk == 0) break;
            vm.prank(ALICE);
            amm.redeem(chunk);
            _assertBalancesMatchReserves();
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 6 – two depositors (clean ratio), 6 swaps, both redeem  (12 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace6_TwoDepositorsThenSwaps() public {
        // Tx 1: Alice seeds 4000:8000
        vm.prank(ALICE);
        amm.deposit(4000 ether, 8000 ether);
        uint aliceShares = amm.minted(ALICE);
        _assertBalancesMatchReserves();

        // Tx 2: Bob deposits same ratio 1000:2000 (exactly proportional)
        vm.prank(BOB);
        amm.deposit(1000 ether, 2000 ether);
        uint bobShares = amm.minted(BOB);
        assertEq(amm.supply(), aliceShares + bobShares);
        _assertBalancesMatchReserves();

        // Tx 3-8: six swaps by both users
        vm.prank(BOB);   amm.swap(address(t0), 200 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(BOB);   amm.swap(address(t1), 100 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(ALICE); amm.swap(address(t0), 300 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(BOB);   amm.swap(address(t1), 400 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(ALICE); amm.swap(address(t0), 100 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(BOB);   amm.swap(address(t1), 200 ether, 0);
        _assertBalancesMatchReserves();

        // Tx 9: Bob redeems his shares (supply > bobShares since Alice still holds)
        vm.prank(BOB);
        amm.redeem(bobShares);
        assertEq(amm.minted(BOB), 0);
        _assertBalancesMatchReserves();

        // Tx 10-12: Alice redeems in 3 steps (pre-compute before prank)
        uint s1 = amm.minted(ALICE) / 2;
        vm.prank(ALICE);
        amm.redeem(s1);
        _assertBalancesMatchReserves();

        uint s2 = amm.minted(ALICE) / 2;
        vm.prank(ALICE);
        amm.redeem(s2);
        _assertBalancesMatchReserves();

        uint s3 = amm.minted(ALICE) / 2;
        vm.prank(ALICE);
        amm.redeem(s3);
        _assertBalancesMatchReserves();
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 7 – progressive partial redeems between swaps  (11 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace7_ProgressiveRedeems() public {
        // Tx 1: Alice deposits
        vm.prank(ALICE);
        amm.deposit(6000 ether, 3000 ether);
        // ratio is 2:1 (t0:t1)

        // Tx 2: swap t0 → t1
        vm.prank(BOB); amm.swap(address(t0), 500 ether, 0);
        _assertBalancesMatchReserves();

        // Tx 3: Alice redeems 1/4 of her shares
        uint q = amm.minted(ALICE) / 4;
        vm.prank(ALICE);
        amm.redeem(q);
        _assertBalancesMatchReserves();

        // Tx 4: swap t1 → t0
        vm.prank(BOB); amm.swap(address(t1), 400 ether, 0);
        _assertBalancesMatchReserves();

        // Tx 5: Alice redeems 1/4 of remaining
        q = amm.minted(ALICE) / 4;
        vm.prank(ALICE);
        amm.redeem(q);
        _assertBalancesMatchReserves();

        // Tx 6: swap t0 → t1
        vm.prank(BOB); amm.swap(address(t0), 300 ether, 0);
        _assertBalancesMatchReserves();

        // Tx 7: Alice redeems 1/4 of remaining
        q = amm.minted(ALICE) / 4;
        vm.prank(ALICE);
        amm.redeem(q);
        _assertBalancesMatchReserves();

        // Tx 8-11: 3 more swaps then a final redeem
        vm.prank(BOB); amm.swap(address(t1), 200 ether, 0);
        vm.prank(BOB); amm.swap(address(t0), 100 ether, 0);
        vm.prank(BOB); amm.swap(address(t1), 50 ether, 0);
        _assertBalancesMatchReserves();

        // Pre-compute minted before prank to avoid prank-consumption by the staticcall
        uint finalChunk = amm.minted(ALICE) / 3;
        vm.prank(ALICE);
        amm.redeem(finalChunk);
        _assertBalancesMatchReserves();
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 8 – swap output correctness: verify exact amounts  (6 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace8_SwapOutputAmounts() public {
        // Tx 1: deposit 1000:1000 (symmetric pool)
        vm.prank(ALICE);
        amm.deposit(1000 ether, 1000 ether);

        // Tx 2: Bob swaps 100 t0 → t1, verify his t1 received
        uint bobT1Before = t1.balanceOf(BOB);
        uint r0 = amm.r0(); uint r1 = amm.r1();
        uint expectedOut = _expectedOut(100 ether, r0, r1);
        vm.prank(BOB);
        amm.swap(address(t0), 100 ether, expectedOut);   // x_out_min = exact expected
        assertEq(t1.balanceOf(BOB) - bobT1Before, expectedOut, "Bob t1 received");
        _assertBalancesMatchReserves();

        // Tx 3: Bob swaps 100 t1 → t0, verify t0 received
        uint bobT0Before = t0.balanceOf(BOB);
        r0 = amm.r0(); r1 = amm.r1();
        expectedOut = _expectedOut(100 ether, r1, r0);
        vm.prank(BOB);
        amm.swap(address(t1), 100 ether, expectedOut);
        assertEq(t0.balanceOf(BOB) - bobT0Before, expectedOut, "Bob t0 received");
        _assertBalancesMatchReserves();

        // Tx 4: another swap
        bobT1Before = t1.balanceOf(BOB);
        r0 = amm.r0(); r1 = amm.r1();
        expectedOut = _expectedOut(200 ether, r0, r1);
        vm.prank(BOB);
        amm.swap(address(t0), 200 ether, expectedOut);
        assertEq(t1.balanceOf(BOB) - bobT1Before, expectedOut);
        _assertBalancesMatchReserves();

        // Tx 5: Alice redeems a portion (pre-compute to avoid prank consumption)
        uint aliceChunk = amm.minted(ALICE) / 4;
        vm.prank(ALICE);
        amm.redeem(aliceChunk);
        _assertBalancesMatchReserves();

        // Tx 6: one more swap after partial redemption
        vm.prank(BOB);
        amm.swap(address(t1), 50 ether, 0);
        _assertBalancesMatchReserves();
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 9 – three depositors (clean ratios), interleaved swaps, all redeem (14 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace9_InterleavedDepositsAndSwaps() public {
        // All deposits happen first with clean proportional amounts, then swaps.
        // Tx 1: Alice seeds 2000:2000
        vm.prank(ALICE);
        amm.deposit(2000 ether, 2000 ether);
        uint aliceShares = amm.minted(ALICE);
        _assertBalancesMatchReserves();

        // Tx 2: Bob deposits same ratio 400:400 (exact proportion)
        vm.prank(BOB);
        amm.deposit(400 ether, 400 ether);
        uint bobShares = amm.minted(BOB);
        assertEq(amm.supply(), aliceShares + bobShares);
        _assertBalancesMatchReserves();

        // Tx 3: Carol deposits same ratio 200:200 (exact proportion)
        vm.prank(CAROL);
        amm.deposit(200 ether, 200 ether);
        uint carolShares = amm.minted(CAROL);
        assertEq(amm.supply(), aliceShares + bobShares + carolShares);
        _assertBalancesMatchReserves();

        // Tx 4-10: alternating swaps by all users
        vm.prank(BOB);   amm.swap(address(t0), 100 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(ALICE); amm.swap(address(t0), 150 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(BOB);   amm.swap(address(t1), 120 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(ALICE); amm.swap(address(t0), 80 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(BOB);   amm.swap(address(t1), 200 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(ALICE); amm.swap(address(t0), 50 ether, 0);
        _assertBalancesMatchReserves();
        vm.prank(CAROL); amm.swap(address(t0), 70 ether, 0);
        _assertBalancesMatchReserves();

        // Tx 11: Carol redeems (supply > carolShares since Alice+Bob still hold)
        vm.prank(CAROL);
        amm.redeem(carolShares);
        assertEq(amm.minted(CAROL), 0);
        _assertBalancesMatchReserves();

        // Tx 12: Bob redeems half (pre-compute before prank)
        uint bobHalf = bobShares / 2;
        vm.prank(BOB);
        amm.redeem(bobHalf);
        _assertBalancesMatchReserves();

        // Tx 13: Bob redeems remaining half
        uint bobRem = amm.minted(BOB) / 2;
        vm.prank(BOB);
        amm.redeem(bobRem);
        _assertBalancesMatchReserves();

        // Tx 14: Alice redeems a quarter
        vm.prank(ALICE);
        amm.redeem(aliceShares / 4);
        _assertBalancesMatchReserves();
    }

    // ════════════════════════════════════════════════════════════════════════
    // TEST 10 – full lifecycle: 3 depositors (clean ratios), heavy swap activity (20 txs)
    // ════════════════════════════════════════════════════════════════════════
    function test_Trace10_FullLifecycle() public {
        // All 3 deposits happen upfront with exact proportional amounts.
        // Tx 1: Alice seeds 5000:2000
        vm.prank(ALICE);
        amm.deposit(5000 ether, 2000 ether);
        uint aliceShares = amm.minted(ALICE); // = 5000 (first deposit, toMint = x0)
        assertEq(amm.supply(), 5000 ether);
        _assertBalancesMatchReserves();

        // Tx 2: Bob deposits same 5:2 ratio – 1000:400 (exact proportion)
        vm.prank(BOB);
        amm.deposit(1000 ether, 400 ether);
        uint bobShares = amm.minted(BOB);
        _assertBalancesMatchReserves();

        // Tx 3: Carol deposits same 5:2 ratio – 500:200 (exact proportion)
        vm.prank(CAROL);
        amm.deposit(500 ether, 200 ether);
        uint carolShares = amm.minted(CAROL);
        assertEq(amm.supply(), aliceShares + bobShares + carolShares);
        _assertBalancesMatchReserves();

        // Tx 4-10: intensive swap phase (7 swaps)
        uint k;
        k = amm.r0() * amm.r1();
        vm.prank(BOB);   amm.swap(address(t0), 100 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        k = amm.r0() * amm.r1();
        vm.prank(BOB);   amm.swap(address(t1), 50 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        k = amm.r0() * amm.r1();
        vm.prank(CAROL); amm.swap(address(t1), 300 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        k = amm.r0() * amm.r1();
        vm.prank(ALICE); amm.swap(address(t0), 300 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        k = amm.r0() * amm.r1();
        vm.prank(BOB);   amm.swap(address(t1), 250 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        k = amm.r0() * amm.r1();
        vm.prank(CAROL); amm.swap(address(t0), 100 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        k = amm.r0() * amm.r1();
        vm.prank(ALICE); amm.swap(address(t1), 400 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        // Tx 11-13: three more swaps
        k = amm.r0() * amm.r1();
        vm.prank(BOB);   amm.swap(address(t0), 150 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        k = amm.r0() * amm.r1();
        vm.prank(CAROL); amm.swap(address(t1), 80 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        k = amm.r0() * amm.r1();
        vm.prank(ALICE); amm.swap(address(t0), 200 ether, 0);
        assertGe(amm.r0() * amm.r1(), k);
        _assertBalancesMatchReserves();

        // Tx 14: Carol redeems fully (supply > carolShares since Alice+Bob still hold)
        vm.prank(CAROL);
        amm.redeem(carolShares);
        assertEq(amm.minted(CAROL), 0);
        _assertBalancesMatchReserves();

        // Tx 15-16: Bob redeems in two steps (pre-compute before prank)
        vm.prank(BOB);
        amm.redeem(bobShares / 2);
        _assertBalancesMatchReserves();

        uint bobRem = amm.minted(BOB) / 2;
        vm.prank(BOB);
        amm.redeem(bobRem);
        _assertBalancesMatchReserves();

        // Tx 17-20: Alice redeems progressively (pre-compute before prank)
        vm.prank(ALICE);
        amm.redeem(aliceShares / 4);
        _assertBalancesMatchReserves();

        uint a2 = amm.minted(ALICE) / 3;
        vm.prank(ALICE);
        amm.redeem(a2);
        _assertBalancesMatchReserves();

        uint a3 = amm.minted(ALICE) / 4;
        vm.prank(ALICE);
        amm.redeem(a3);
        _assertBalancesMatchReserves();

        uint a4 = amm.minted(ALICE) / 4;
        vm.prank(ALICE);
        amm.redeem(a4);
        _assertBalancesMatchReserves();
    }
}
