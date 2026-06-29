// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {ReactiveHarness, RscMode} from "../src/ReactiveHarness.sol";
import {IReactive, LogRecord} from "@reactive-lib/IReactive.sol";
import {CrossChainOracleOrigin} from "../examples/CrossChainOracleOrigin.sol";
import {CrossChainOracleDestination} from "../examples/CrossChainOracleDestination.sol";
import {CrossChainOracleReactive} from "../examples/CrossChainOracleReactive.sol";

/// @title ReactiveOracleE2ETest
/// @notice End-to-end tests for the cross-chain oracle using ReactiveHarness
/// @dev Demonstrates the full emit -> react -> callback -> destination state assertion flow
contract ReactiveOracleE2ETest is ReactiveHarness {
    uint256 constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant LASNA_CHAIN_ID = 5318007;
    bytes32 constant ETH_USD = keccak256("ETH/USD");
    bytes32 constant BTC_USD = keccak256("BTC/USD");

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    CrossChainOracleOrigin public origin;
    CrossChainOracleDestination public destination;
    CrossChainOracleReactive public reactive;

    /// @notice Deploy contracts on their respective chains
    function setUp() public override {
        super.setUp();

        // Deploy Origin on Sepolia
        vm.chainId(SEPOLIA_CHAIN_ID);
        origin = new CrossChainOracleOrigin();

        // Deploy Destination on Sepolia
        destination = new CrossChainOracleDestination();

        // Deploy Reactive on Lasna (with RNK proxy for constructor subscription)
        vm.chainId(LASNA_CHAIN_ID);
        reactive = new CrossChainOracleReactive(
            address(origin),
            SEPOLIA_CHAIN_ID,
            address(destination),
            SEPOLIA_CHAIN_ID,
            address(subscriptionProxy) // Use the mock proxy from the harness
        );
    }

    // =========================================================================
    // Deployment Tests
    // =========================================================================

    /// @notice Test all contracts deploy correctly
    function test_Deployment() public {
        assertEq(origin.getPrice(ETH_USD), 0);
        assertEq(destination.getReceivedPrice(ETH_USD), 0);
        assertEq(reactive.ORIGIN_CONTRACT(), address(origin));
        assertEq(reactive.DESTINATION_CONTRACT(), address(destination));
        assertEq(reactive.ORIGIN_CHAIN_ID(), SEPOLIA_CHAIN_ID);
    }

    // =========================================================================
    // Update Event Tests
    // =========================================================================

    /// @notice Test price update on origin emits the right event
    function test_OriginUpdatePrice() public {
        vm.chainId(SEPOLIA_CHAIN_ID);

        uint256 price = 2000e8;
        vm.recordLogs();
        vm.prank(alice);
        origin.updatePrice(ETH_USD, price);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1, "Should emit one event");
        assertEq(entries[0].topics[0], keccak256("PriceUpdated(address,bytes32,uint256,uint256)"));
        assertEq(entries[0].topics[1], bytes32(uint256(uint160(alice))), "Submitter should be alice");
        assertEq(entries[0].topics[2], bytes32(ETH_USD), "AssetId should be ETH/USD");
        assertEq(origin.latestPrices(ETH_USD), price);
    }

    /// @notice Test origin rejects zero price
    function test_OriginRevertZeroPrice() public {
        vm.chainId(SEPOLIA_CHAIN_ID);
        vm.prank(alice);
        vm.expectRevert("Price must be greater than 0");
        origin.updatePrice(ETH_USD, 0);
    }

    // =========================================================================
    // Wrong Chain/Contract Skip Tests
    // =========================================================================

    /// @notice Test reactive contract skips events from wrong chain
    function test_ReactiveSkipsWrongChain() public {
        vm.chainId(LASNA_CHAIN_ID);

        // Simulate an event from the wrong chain
        LogRecord memory log = LogRecord({
            chainId: LASNA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(alice)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(2000e8, 1000000)
        });

        vm.recordLogs();
        reactive.react(log);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0, "Should not emit any events for wrong chain");
    }

    /// @notice Test reactive contract skips events from wrong contract
    function test_ReactiveSkipsWrongContract() public {
        vm.chainId(LASNA_CHAIN_ID);

        // Simulate an event from the wrong contract
        LogRecord memory log = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(0xdead),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(alice)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(2000e8, 1000000)
        });

        vm.recordLogs();
        reactive.react(log);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 0, "Should not emit any events for wrong contract");
    }

    // =========================================================================
    // Threshold Tests (below, above, exact boundary)
    // =========================================================================

    /// @notice Test price below 0.5% threshold is NOT relayed
    function test_BelowThresholdDoesNotRelay() public {
        vm.chainId(LASNA_CHAIN_ID);

        uint256 initialPrice = 2000e8;

        // First price is always relayed
        LogRecord memory log1 = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(alice)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(initialPrice, 1000000)
        });
        reactive.react(log1);
        assertEq(reactive.lastRelayedPrices(ETH_USD), initialPrice);

        // Small change (0.1% = 2e8 increase) - below 0.5% threshold
        uint256 smallChangePrice = 2002e8;
        LogRecord memory log2 = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(bob)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(smallChangePrice, 2000000)
        });

        vm.recordLogs();
        reactive.react(log2);

        // Check no Callback was emitted
        bool foundCallback;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == CALLBACK_EVENT_SIG) {
                foundCallback = true;
                break;
            }
        }
        assertFalse(foundCallback, "Should NOT emit Callback for small price change");
        assertEq(reactive.lastRelayedPrices(ETH_USD), initialPrice, "Price should NOT be updated in storage");
    }

    /// @notice Test price above 0.5% threshold IS relayed
    function test_AboveThresholdRelays() public {
        vm.chainId(LASNA_CHAIN_ID);

        uint256 initialPrice = 2000e8;

        // First price is always relayed
        LogRecord memory log1 = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(alice)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(initialPrice, 1000000)
        });
        reactive.react(log1);

        // Large change (1% = 20e8 increase) - above 0.5% threshold
        uint256 largeChangePrice = 2020e8;
        LogRecord memory log2 = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(bob)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(largeChangePrice, 2000000)
        });

        vm.recordLogs();
        reactive.react(log2);

        // Check Callback was emitted
        bool foundCallback;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == CALLBACK_EVENT_SIG) {
                foundCallback = true;
                break;
            }
        }
        assertTrue(foundCallback, "Should emit Callback for large price change");
        assertEq(reactive.lastRelayedPrices(ETH_USD), largeChangePrice, "Price SHOULD be updated in storage");
    }

    /// @notice Test exact 0.5% boundary is relayed (>=)
    function test_ExactBoundaryRelays() public {
        vm.chainId(LASNA_CHAIN_ID);

        uint256 initialPrice = 2000e8;

        // First price
        LogRecord memory log1 = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(alice)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(initialPrice, 1000000)
        });
        reactive.react(log1);

        // Exactly 0.5% change = 10e8 increase
        uint256 boundaryPrice = 2010e8;
        LogRecord memory log2 = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(bob)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(boundaryPrice, 2000000)
        });

        vm.recordLogs();
        reactive.react(log2);

        // Exactly 0.5% (50 bps) should relay since threshold is >= 50 bps
        bool foundCallback;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == CALLBACK_EVENT_SIG) {
                foundCallback = true;
                break;
            }
        }
        assertTrue(foundCallback, "Should emit Callback for exactly 0.5% change");
        assertEq(reactive.lastRelayedPrices(ETH_USD), boundaryPrice);
    }

    // =========================================================================
    // Multiple Assets Test
    // =========================================================================

    /// @notice Test multiple assets are tracked independently
    function test_MultipleAssets() public {
        vm.chainId(LASNA_CHAIN_ID);

        LogRecord memory logEth = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(alice)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(2000e8, 1000000)
        });
        reactive.react(logEth);

        LogRecord memory logBtc = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(reactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(alice)),
            topic2: uint256(BTC_USD),
            topic3: 0,
            data: abi.encode(30000e8, 1000000)
        });
        reactive.react(logBtc);

        assertEq(reactive.lastRelayedPrices(ETH_USD), 2000e8);
        assertEq(reactive.lastRelayedPrices(BTC_USD), 30000e8);
    }

    // =========================================================================
    // Constructor Subscription Test
    // =========================================================================

    /// @notice Test constructor subscription via proxy
    function test_ConstructorSubscription() public {
        vm.chainId(LASNA_CHAIN_ID);

        // The setUp already deployed with subscriptionProxy, check subscription
        assertSubscriptionRecorded(
            address(origin),
            SEPOLIA_CHAIN_ID,
            reactive.PRICE_UPDATED_TOPIC_0()
        );
    }

    /// @notice Test constructor with address(0) proxy works (RVM mode)
    function test_ConstructorWithoutProxy() public {
        vm.chainId(LASNA_CHAIN_ID);

        // Deploy without proxy (RVM mode)
        CrossChainOracleReactive r = new CrossChainOracleReactive(
            address(origin),
            SEPOLIA_CHAIN_ID,
            address(destination),
            SEPOLIA_CHAIN_ID,
            address(0)
        );

        assertEq(r.ORIGIN_CONTRACT(), address(origin));
        assertEq(r.DESTINATION_CONTRACT(), address(destination));
    }

    // =========================================================================
    // Full Integration Test (THE KEY TEST)
    // =========================================================================

    /// @notice Full end-to-end test: emit on origin -> react -> callback -> destination state
    /// @dev This is the key value proposition of rfk: you can assert on destination state
    function test_FullIntegration() public {
        // 1. Emit a PriceUpdated on origin (Sepolia)
        vm.chainId(SEPOLIA_CHAIN_ID);
        vm.recordLogs();
        vm.prank(alice);
        origin.updatePrice(ETH_USD, 2000e8);

        // 2. Let reactive process it (switch to Lasna chain where reactive lives)
        vm.chainId(LASNA_CHAIN_ID);
        emitAndReact(address(origin), address(reactive));

        // 3. Deliver callbacks to destination
        deliverCallbacks(address(reactive), address(destination), address(0));

        // 4. ASSERT ON DESTINATION STATE
        assertEq(
            destination.receivedPrices(ETH_USD),
            2000e8,
            "Destination should have the price after full flow"
        );
        assertTrue(
            destination.receiptTimestamps(ETH_USD) > 0,
            "Destination should have a receipt timestamp"
        );
    }

    /// @notice Full integration test checking price decrease
    function test_FullIntegrationPriceDecrease() public {
        // First, store initial price
        vm.chainId(SEPOLIA_CHAIN_ID);
        vm.recordLogs();
        vm.prank(alice);
        origin.updatePrice(ETH_USD, 2000e8);

        vm.chainId(LASNA_CHAIN_ID);

        // Process first price
        emitAndReact(address(origin), address(reactive));
        deliverCallbacks(address(reactive), address(destination), address(0));

        // Assert first price was delivered
        assertEq(destination.receivedPrices(ETH_USD), 2000e8);

        // Now emit a lower price
        vm.chainId(SEPOLIA_CHAIN_ID);
        vm.recordLogs();
        vm.prank(alice);
        origin.updatePrice(ETH_USD, 1800e8); // 10% decrease

        vm.chainId(LASNA_CHAIN_ID);
        emitAndReact(address(origin), address(reactive));
        deliverCallbacks(address(reactive), address(destination), address(0));

        // Assert new price on destination
        assertEq(
            destination.receivedPrices(ETH_USD),
            1800e8,
            "Destination should have the decreased price"
        );
    }

    /// @notice Full integration test with multiple updates
    function test_FullIntegrationMultipleUpdates() public {
        // First price for ETH
        vm.chainId(SEPOLIA_CHAIN_ID);
        vm.recordLogs();
        vm.prank(alice);
        origin.updatePrice(ETH_USD, 2000e8);

        vm.chainId(LASNA_CHAIN_ID);
        emitAndReact(address(origin), address(reactive));
        deliverCallbacks(address(reactive), address(destination), address(0));
        assertEq(destination.receivedPrices(ETH_USD), 2000e8);

        // Second price for ETH (large change to trigger relay)
        vm.chainId(SEPOLIA_CHAIN_ID);
        vm.recordLogs();
        vm.prank(alice);
        origin.updatePrice(ETH_USD, 2500e8); // 25% increase

        vm.chainId(LASNA_CHAIN_ID);
        emitAndReact(address(origin), address(reactive));
        deliverCallbacks(address(reactive), address(destination), address(0));
        assertEq(destination.receivedPrices(ETH_USD), 2500e8);

        // Small change should NOT trigger relay
        vm.chainId(SEPOLIA_CHAIN_ID);
        vm.recordLogs();
        vm.prank(alice);
        origin.updatePrice(ETH_USD, 2502e8); // 0.08% increase

        vm.chainId(LASNA_CHAIN_ID);
        emitAndReact(address(origin), address(reactive));
        // deliverCallbacks would fail because there's no callback for small changes
        // Just verify the callback was NOT emitted
        assertCallbackEmittedNot(address(destination));
    }

    /// @notice Helper: assert a callback was NOT emitted to the destination
    function assertCallbackEmittedNot(address destinationContract) internal view {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length == 0) continue;
            if (entries[i].topics[0] != CALLBACK_EVENT_SIG) continue;

            (, address callbackContract,) = abi.decode(entries[i].data, (uint256, address, bytes));
            if (callbackContract == destinationContract) {
                revert("Callback was emitted but should not have been");
            }
        }
    }

    /// @notice Test destination unauthorized access still works with our harness
    function test_DestinationUnauthorizedReverts() public {
        vm.chainId(SEPOLIA_CHAIN_ID);
        vm.prank(eve);
        vm.expectRevert("Unauthorized: only callback proxy can call receivePrice");
        destination.receivePrice(ETH_USD, 2000e8, block.timestamp);
    }

    /// @notice Test RVM mode with address(0) subscription proxy
    function test_RvmModeWithHarness() public {
        setRscMode(RscMode.RVM);

        vm.chainId(LASNA_CHAIN_ID);
        CrossChainOracleReactive rvmReactive = new CrossChainOracleReactive(
            address(origin),
            SEPOLIA_CHAIN_ID,
            address(destination),
            SEPOLIA_CHAIN_ID,
            address(0) // No proxy in RVM
        );

        // Should still process events
        LogRecord memory log = LogRecord({
            chainId: SEPOLIA_CHAIN_ID,
            _contract: address(origin),
            topic0: uint256(rvmReactive.PRICE_UPDATED_TOPIC_0()),
            topic1: uint256(uint160(alice)),
            topic2: uint256(ETH_USD),
            topic3: 0,
            data: abi.encode(2000e8, 1000000)
        });

        vm.recordLogs();
        rvmReactive.react(log);

        bool foundCallback;
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == CALLBACK_EVENT_SIG) {
                foundCallback = true;
                break;
            }
        }
        assertTrue(foundCallback, "RVM reactive should still emit callbacks");
    }

    address eve = makeAddr("eve");
}
