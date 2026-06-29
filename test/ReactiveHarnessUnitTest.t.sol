// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {ReactiveHarness, RscMode} from "../src/ReactiveHarness.sol";
import {ReactiveRegistry, ChainConfig} from "../src/ReactiveRegistry.sol";

/// @title ReactiveHarnessUnitTest
/// @notice Unit tests for the ReactiveHarness itself
contract ReactiveHarnessUnitTest is ReactiveHarness {
    // Events for testing log capture
    event TestEvent(address indexed sender, uint256 value);

    /// @notice Test emitAndReact captures logs correctly
    function test_EmitAndReactCapturesLogs() public {
        vm.recordLogs();
        emit TestEvent(address(this), 42);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Should record 1 log");

        bytes32 expectedSig = keccak256("TestEvent(address,uint256)");
        assertEq(logs[0].topics[0], expectedSig, "Topic0 should be event sig");
    }

    /// @notice Test deliverCallbacks no-ops when no Callback events exist
    function test_DeliverCallbacksNoOpWhenNoCallbacks() public {
        vm.recordLogs();
        emit TestEvent(address(this), 42);

        // This should not revert since there are no Callback events
        deliverCallbacks(address(0), address(0), address(0));
    }

    /// @notice Test RNK vs RVM mode
    function test_RnkMode() public {
        assertTrue(isRnkMode(), "Default mode should be RNK");
        assertFalse(isRvmMode(), "Should not be RVM by default");
        assertTrue(getSubscriptionProxyAddress() != address(0), "RNK should have proxy address");
        assertEq(getSubscriptionProxyAddress(), address(subscriptionProxy), "RNK proxy should match");
    }

    /// @notice Test RVM mode
    function test_RvmMode() public {
        setRscMode(RscMode.RVM);
        assertTrue(isRvmMode(), "Should be RVM after setting");
        assertFalse(isRnkMode(), "Should not be RNK");
        assertEq(getSubscriptionProxyAddress(), address(0), "RVM should return address(0) for proxy");
    }

    /// @notice Test debug mode enable/disable
    function test_DebugMode() public {
        assertFalse(debugEnabled, "Debug should be disabled by default");
        enableDebug();
        assertTrue(debugEnabled, "Debug should be enabled after enableDebug()");
        disableDebug();
        assertFalse(debugEnabled, "Debug should be disabled after disableDebug()");
    }

    /// @notice Test assertSubscriptionRecorded
    function test_AssertSubscriptionRecorded() public {
        address origin = makeAddr("origin");
        uint256 chainId = 11155111;
        bytes32 topic0 = keccak256("SomeEvent()");

        // Subscribe via the proxy
        subscriptionProxy.subscribe(origin, chainId, uint256(topic0), 0, 0, 0, 100_000);

        // Assert it was recorded
        assertSubscriptionRecorded(origin, chainId, topic0);
    }

    /// @notice Test registry lookups
    function test_RegistryLookups() public {
        // Sepolia
        ChainConfig memory sepolia = ReactiveRegistry.getChainConfig(11155111);
        assertEq(sepolia.chainId, 11155111, "Sepolia chain ID");
        assertEq(sepolia.name, "Sepolia", "Sepolia name");
        assertEq(sepolia.callbackProxy, 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA, "Sepolia callback proxy");

        // Lasna
        ChainConfig memory lasna = ReactiveRegistry.getChainConfig(5318007);
        assertEq(lasna.chainId, 5318007, "Lasna chain ID");
        assertEq(lasna.name, "Lasna", "Lasna name");

        // Helper getters
        assertEq(ReactiveRegistry.getCallbackProxy(11155111), sepolia.callbackProxy);
        assertEq(ReactiveRegistry.getSystemContract(11155111), sepolia.systemContract);
        assertEq(ReactiveRegistry.getSubscriptionProxy(11155111), sepolia.subscriptionProxy);

        // supportedChains
        ChainConfig[] memory chains = ReactiveRegistry.supportedChains();
        assertEq(chains.length, 2, "Should support 2 chains");
        assertEq(chains[0].chainId, 11155111, "First chain should be Sepolia");
        assertEq(chains[1].chainId, 5318007, "Second chain should be Lasna");
    }
}
