#!/usr/bin/env bash
set -euo pipefail

# new-rsc.sh — Scaffold a new Reactive Smart Contract project with rfk
#
# Usage:
#   ./new-rsc.sh <project-name> [origin-chain-id] [destination-chain-id]
#
# Examples:
#   ./new-rsc.sh my-oracle
#   ./new-rsc.sh my-oracle 11155111 11155111  (Sepolia → Sepolia)

PROJECT_NAME="${1:?Usage: new-rsc.sh <project-name> [origin-chain-id] [destination-chain-id]}"
ORIGIN_CHAIN="${2:-11155111}"
DEST_CHAIN="${3:-11155111}"

echo "==> Scaffolding Reactive Smart Contract project: $PROJECT_NAME"

# Create Foundry project
forge init --offline "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Add rfk as a dependency
mkdir -p lib/rfk
echo "rfk (Reactive Foundry Kit) — add ../rfk as a git submodule or copy lib/ manually"
echo "  git submodule add <rfk-repo-url> lib/rfk"

# Create template contracts
cat > src/Origin.sol << 'SOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Origin
/// @notice Origin contract that emits events consumed by the Reactive contract
contract Origin {
    event DataUpdated(address indexed submitter, bytes32 indexed key, uint256 value, uint256 timestamp);

    mapping(bytes32 => uint256) public latestValues;
    mapping(bytes32 => uint256) public lastTimestamps;

    function updateData(bytes32 key, uint256 value) external {
        require(value > 0, "Value must be greater than 0");
        latestValues[key] = value;
        lastTimestamps[key] = block.timestamp;
        emit DataUpdated(msg.sender, key, value, block.timestamp);
    }

    function getValue(bytes32 key) external view returns (uint256) {
        return latestValues[key];
    }
}
SOL

cat > src/Destination.sol << 'SOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Destination
/// @notice Destination contract that receives data via Reactive Network callback
contract Destination {
    address public constant CALLBACK_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    event DataReceived(bytes32 indexed key, uint256 value, uint256 timestamp, address indexed originTxOrigin);

    mapping(bytes32 => uint256) public receivedValues;
    mapping(bytes32 => uint256) public receiptTimestamps;

    function receiveData(bytes32 key, uint256 value, uint256 timestamp) external {
        if (msg.sender != CALLBACK_PROXY) {
            revert("Unauthorized: only callback proxy can call receiveData");
        }
        require(value > 0, "Value must be greater than 0");
        require(timestamp > 0, "Timestamp must be greater than 0");

        receivedValues[key] = value;
        receiptTimestamps[key] = block.timestamp;

        address originTxOrigin;
        assembly { originTxOrigin := calldataload(0) }

        emit DataReceived(key, value, timestamp, originTxOrigin);
    }

    function getReceivedValue(bytes32 key) external view returns (uint256) {
        return receivedValues[key];
    }
}
SOL

cat > src/Reactive.sol << 'SOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IReactive, LogRecord, ISubscriptionProxy} from "@reactive-lib/IReactive.sol";

/// @title Reactive
/// @notice Reactive contract that monitors Origin events and triggers Destination callbacks
contract Reactive is IReactive {
    address public immutable ORIGIN_CONTRACT;
    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable DESTINATION_CONTRACT;
    uint256 public immutable DESTINATION_CHAIN_ID;

    bytes32 public constant DATA_UPDATED_TOPIC_0 = keccak256("DataUpdated(address,bytes32,uint256,uint256)");
    uint256 public constant CALLBACK_GAS_LIMIT = 200_000;

    event DataUpdateReceived(bytes32 indexed key, uint256 value, uint256 timestamp, address indexed submitter, bool relayed);
    event SubscriptionError(string reason);

    constructor(
        address _originContract,
        uint256 _originChainId,
        address _destinationContract,
        uint256 _destinationChainId,
        address _subscriptionProxy
    ) {
        ORIGIN_CONTRACT = _originContract;
        ORIGIN_CHAIN_ID = _originChainId;
        DESTINATION_CONTRACT = _destinationContract;
        DESTINATION_CHAIN_ID = _destinationChainId;

        if (_subscriptionProxy != address(0)) {
            try ISubscriptionProxy(_subscriptionProxy).subscribe(
                _originContract, _originChainId, uint256(DATA_UPDATED_TOPIC_0), 0, 0, 0, CALLBACK_GAS_LIMIT
            ) returns (bool success) {
                if (!success) emit SubscriptionError("Subscription returned false");
            } catch Error(string memory reason) {
                emit SubscriptionError(reason);
            } catch (bytes memory lowLevelData) {
                emit SubscriptionError(string(abi.encodePacked("Subscription failed: ", lowLevelData)));
            }
        } else {
            emit SubscriptionError("No subscription proxy provided");
        }
    }

    function react(LogRecord memory log) external override {
        if (log._contract != ORIGIN_CONTRACT || log.chainId != ORIGIN_CHAIN_ID) return;
        if (log.topic0 != uint256(DATA_UPDATED_TOPIC_0)) return;

        address submitter = address(uint160(log.topic1));
        bytes32 key = bytes32(log.topic2);
        (uint256 value, uint256 timestamp) = abi.decode(log.data, (uint256, uint256));

        require(value > 0, "Value must be greater than 0");
        require(timestamp > 0, "Timestamp must be greater than 0");

        bytes memory payload = abi.encodePacked(
            address(0),
            abi.encodeWithSelector(bytes4(keccak256("receiveData(bytes32,uint256,uint256)")), key, value, timestamp)
        );

        emit Callback(DESTINATION_CHAIN_ID, DESTINATION_CONTRACT, CALLBACK_GAS_LIMIT, payload);
        emit DataUpdateReceived(key, value, timestamp, submitter, true);
    }
}
SOL

cat > test/E2ETest.t.sol << 'SOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReactiveHarness} from "rfk/ReactiveHarness.sol";
import {ReactiveRegistry} from "rfk/ReactiveRegistry.sol";
import "../src/Origin.sol";
import "../src/Destination.sol";
import "../src/Reactive.sol";

contract E2ETest is ReactiveHarness {
    uint256 constant ORIGIN_CHAIN_ID = '$ORIGIN_CHAIN';
    uint256 constant DEST_CHAIN_ID = '$DEST_CHAIN';
    bytes32 constant MY_KEY = keccak256("my-key");

    Origin origin;
    Destination destination;
    Reactive reactive;

    function setUp() public override {
        super.setUp();

        vm.chainId(ORIGIN_CHAIN_ID);
        origin = new Origin();
        destination = new Destination();

        vm.chainId(DEST_CHAIN_ID);
        reactive = new Reactive(
            address(origin), ORIGIN_CHAIN_ID,
            address(destination), DEST_CHAIN_ID,
            address(subscriptionProxy)
        );
    }

    function test_FullIntegration() public {
        vm.chainId(ORIGIN_CHAIN_ID);
        vm.recordLogs();
        origin.updateData(MY_KEY, 42);

        vm.chainId(DEST_CHAIN_ID);
        emitAndReact(address(origin), address(reactive));
        deliverCallbacks(address(reactive), address(destination), address(0));

        assertEq(destination.getReceivedValue(MY_KEY), 42, "Destination should have the value");
    }
}
SOL

# Update foundry.toml with remappings
cat >> foundry.toml << 'TOM'

remappings = ["rfk/=lib/rfk/src/"]
TOM

echo ""
echo "==> Done! Reactive Smart Contract project '$PROJECT_NAME' is ready."
echo ""
echo "  cd $PROJECT_NAME"
echo "  forge build"
echo "  forge test -vvv"
echo ""
echo "Edit src/Origin.sol, src/Destination.sol, and src/Reactive.sol to"
echo "implement your own logic. The test in test/E2ETest.t.sol already"
echo "exercises the full emit -> react -> callback -> destination flow."
