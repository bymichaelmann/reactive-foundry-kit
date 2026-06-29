// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import "forge-std/Test.sol";
import {IReactive, LogRecord, ISubscriptionProxy} from "@reactive-lib/IReactive.sol";
import {MockSystemContract, Subscription} from "./mocks/MockSystemContract.sol";
import {MockSubscriptionProxy} from "./mocks/MockSubscriptionProxy.sol";
import {MockCallbackProxy} from "./mocks/MockCallbackProxy.sol";

/// @notice RSC execution mode enum
/// @dev RNK = Reactive Network Kit (subscription proxy available, EOA accessible)
///      RVM = Reactive Virtual Machine (private, no subscription proxy)
enum RscMode {
    RNK,
    RVM
}

/// @title ReactiveHarness
/// @notice Abstract test harness for Reactive Network smart contracts
/// @dev Extends forge-std Test to provide the full RSC testing infrastructure.
///      Deploy this, wire up origin/reactive/destination contracts, and test the
///      full emit -> react -> callback -> destination state assertion flow.
abstract contract ReactiveHarness is Test {
    // -----------------------------------------------------------------------
    // Constants
    // -----------------------------------------------------------------------

    /// @notice Default source chain ID (Sepolia)
    uint256 public constant DEFAULT_CHAIN_ID = 11155111;

    /// @notice Sepolia callback proxy address (from Reactive docs)
    address public constant SEPOLIA_CALLBACK_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    /// @notice Event signature for IReactive.Callback
    bytes32 public constant CALLBACK_EVENT_SIG = keccak256("Callback(uint256,address,uint256,bytes)");

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /// @notice Mock system contract
    MockSystemContract public systemContract;

    /// @notice Mock subscription proxy
    MockSubscriptionProxy public subscriptionProxy;

    /// @notice Mock callback proxy
    MockCallbackProxy public callbackProxy;

    /// @notice Current RSC mode
    RscMode public rscMode;

    /// @notice Whether debug mode is enabled
    bool public debugEnabled;

    /// @notice The chain ID to use for emitted logs in emitAndReact
    uint256 public sourceChainId;

    // -----------------------------------------------------------------------
    // Setup
    // -----------------------------------------------------------------------

    /// @notice Deploy all mocks
    function setUp() public virtual {
        systemContract = new MockSystemContract();
        subscriptionProxy = new MockSubscriptionProxy();
        subscriptionProxy.setSystemContract(address(systemContract));
        callbackProxy = new MockCallbackProxy();
        sourceChainId = DEFAULT_CHAIN_ID;
        rscMode = RscMode.RNK;
        debugEnabled = false;
    }

    // -----------------------------------------------------------------------
    // Mode management
    // -----------------------------------------------------------------------

    /// @notice Set the RSC mode for the current test
    /// @param mode The mode to set (RNK or RVM)
    function setRscMode(RscMode mode) public {
        rscMode = mode;
    }

    /// @notice Check if running in RNK mode
    function isRnkMode() public view returns (bool) {
        return rscMode == RscMode.RNK;
    }

    /// @notice Check if running in RVM mode
    function isRvmMode() public view returns (bool) {
        return rscMode == RscMode.RVM;
    }

    /// @notice Get the subscription proxy address based on current mode
    function getSubscriptionProxyAddress() public view returns (address) {
        if (rscMode == RscMode.RNK) {
            return address(subscriptionProxy);
        }
        return address(0);
    }

    // -----------------------------------------------------------------------
    // Debug mode
    // -----------------------------------------------------------------------

    function enableDebug() public {
        debugEnabled = true;
    }

    function disableDebug() public {
        debugEnabled = false;
    }

    // -----------------------------------------------------------------------
    // Core harness operations
    // -----------------------------------------------------------------------

    /// @notice Translate recorded logs into LogRecords and deliver to rsc.react()
    /// @dev Call vm.recordLogs() before the origin action, then call this.
    /// @param originContract Origin contract (used for debug logging)
    /// @param rsc Reactive contract receiving LogRecords
    function emitAndReact(address originContract, address rsc) public {
        Vm.Log[] memory entries = vm.getRecordedLogs();

        if (debugEnabled) {
            console2.log("emitAndReact: processing ", entries.length, " logs");
            console2.log("  origin contract:");
            console2.log(address(originContract));
        }

        for (uint256 i = 0; i < entries.length; i++) {
            Vm.Log memory entry = entries[i];

            uint256 topic0 = entry.topics.length > 0 ? uint256(entry.topics[0]) : 0;
            uint256 topic1 = entry.topics.length > 1 ? uint256(entry.topics[1]) : 0;
            uint256 topic2 = entry.topics.length > 2 ? uint256(entry.topics[2]) : 0;
            uint256 topic3 = entry.topics.length > 3 ? uint256(entry.topics[3]) : 0;

            LogRecord memory logRecord = LogRecord({
                chainId: sourceChainId,
                _contract: entry.emitter,
                topic0: topic0,
                topic1: topic1,
                topic2: topic2,
                topic3: topic3,
                data: entry.data
            });

            if (debugEnabled) {
                console2.log("  -> LogRecord(chainId=", logRecord.chainId, ")");
                console2.log("      contract:");
                console2.log(address(logRecord._contract));
                console2.log("      topic0:");
                console2.logBytes32(bytes32(logRecord.topic0));
                if (logRecord.topic1 != 0) {
                    console2.log("      topic1:");
                    console2.logBytes32(bytes32(logRecord.topic1));
                }
            }

            IReactive(rsc).react(logRecord);
        }
    }

    /// @notice Capture Callback events from the log buffer and execute them against destination
    /// @dev Reads recorded logs, filters for Callback events, decodes them,
    ///      verifies deployer substitution, and executes the call on destination.
    /// @param rsc Reactive contract (for debug logging)
    /// @param destinationContract Destination contract to call
    /// @param expectedOriginTxOrigin Expected deployer address from first 20 bytes of payload
    function deliverCallbacks(address rsc, address destinationContract, address expectedOriginTxOrigin) public {
        Vm.Log[] memory entries = vm.getRecordedLogs();

        if (debugEnabled) {
            console2.log("deliverCallbacks: processing ", entries.length, " callbacks");
            console2.log("  from rsc:");
            console2.log(address(rsc));
        }

        for (uint256 i = 0; i < entries.length; i++) {
            Vm.Log memory entry = entries[i];

            if (entry.topics.length == 0) continue;
            if (entry.topics[0] != CALLBACK_EVENT_SIG) continue;

            // Decode: event Callback(uint256 chainId, address _contract, uint256 indexed gasLimit, bytes data)
            (uint256 chainId, address callbackContract, bytes memory callbackData) =
                abi.decode(entry.data, (uint256, address, bytes));
            uint256 gasLimit = uint256(entry.topics[1]);

            if (debugEnabled) {
                bytes4 selector;
                if (callbackData.length >= 24) {
                    assembly {
                        selector := mload(add(add(callbackData, 32), 20))
                    }
                }
                console2.log("  -> Callback(chainId=", chainId, ")");
                console2.log("      contract:");
                console2.log(address(callbackContract));
                console2.log("      gasLimit: ", gasLimit);
                console2.log("      selector:");
                console2.logBytes(abi.encodePacked(selector));
            }

            require(callbackData.length >= 20, "Callback data too short");

            // First 20 bytes = deployer address (substituted by RN infra)
            address deployer;
            assembly {
                deployer := shr(96, mload(add(callbackData, 32)))
            }

            if (expectedOriginTxOrigin != address(0)) {
                assertEq(
                    deployer,
                    expectedOriginTxOrigin,
                    "deployer address in callback data should match expectedOriginTxOrigin"
                );
            }

            // Extract calldata (bytes 20+)
            bytes memory callData = new bytes(callbackData.length - 20);
            for (uint256 j = 20; j < callbackData.length; j++) {
                callData[j - 20] = callbackData[j];
            }

            // Simulate callback proxy calling destination
            // Use the real callback proxy address that the destination contract checks
            vm.prank(SEPOLIA_CALLBACK_PROXY);
            (bool success, bytes memory returnData) = destinationContract.call{gas: gasLimit}(callData);

            if (!success) {
                string memory reason = _decodeRevertReason(returnData);
                revert(string(abi.encodePacked("Callback execution failed: ", reason)));
            }

            if (debugEnabled) {
                console2.log("  -> Callback executed successfully");
            }
        }
    }

    // -----------------------------------------------------------------------
    // Assertion helpers
    // -----------------------------------------------------------------------

    /// @notice Assert a subscription was recorded in MockSystemContract
    function assertSubscriptionRecorded(address originContract, uint256 chainId, bytes32 topic0) public view {
        bytes32 key = keccak256(abi.encodePacked(originContract, chainId, topic0));
        Subscription memory sub = systemContract.getSubscription(key);
        assertTrue(sub.originContract != address(0), "Subscription not recorded");
        assertEq(address(sub.originContract), originContract, "Subscription origin mismatch");
        assertEq(sub.chainId, chainId, "Subscription chainId mismatch");
        assertEq(sub.topic0, uint256(topic0), "Subscription topic0 mismatch");
    }

    /// @notice Assert a Callback event was emitted to a specific destination with a specific selector
    function assertCallbackEmitted(address destinationContract, bytes4 selector) public view {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics.length == 0) continue;
            if (entries[i].topics[0] != CALLBACK_EVENT_SIG) continue;

            (, address callbackContract, bytes memory callbackData) =
                abi.decode(entries[i].data, (uint256, address, bytes));

            if (callbackContract != destinationContract) continue;
            if (callbackData.length < 24) continue;

            bytes4 actualSelector;
            assembly {
                actualSelector := mload(add(add(callbackData, 32), 20))
            }
            if (actualSelector == selector) {
                return;
            }
        }
        revert("Callback event not emitted");
    }

    // -----------------------------------------------------------------------
    // Internal helpers
    // -----------------------------------------------------------------------

    /// @notice Decode revert reason from return data
    function _decodeRevertReason(bytes memory returnData) internal pure returns (string memory) {
        if (returnData.length == 0) return "No revert reason";
        if (returnData.length >= 4) {
            bytes4 selector;
            assembly { selector := mload(add(returnData, 32)) }
            if (selector == 0x08c379a0) {
                return abi.decode(returnData, (string));
            }
        }
        return "Unknown revert reason";
    }
}
