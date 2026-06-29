// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice A single subscription record stored by MockSystemContract
struct Subscription {
    address originContract;
    uint256 chainId;
    uint256 topic0;
    uint256 topic1;
    uint256 topic2;
    uint256 topic3;
    uint256 gasLimit;
}

/// @title MockSystemContract
/// @notice A mock of the Reactive Network system contract for testing
/// @dev Simulates subscription management for the Reactive Network
contract MockSystemContract {
    /// @notice Emitted when a subscription is recorded
    /// @param originContract The contract emitting events
    /// @param chainId The chain where events originate
    /// @param topic0 Event signature hash
    /// @param subscriber The address that initiated the subscription
    event SubscriptionRecorded(
        address indexed originContract,
        uint256 indexed chainId,
        uint256 indexed topic0,
        address subscriber
    );

    /// @notice Subscription key: hash(originContract, chainId, topic0)
    mapping(bytes32 => Subscription) public subscriptions;

    /// @notice Array of all subscription keys for enumeration
    bytes32[] public subscriptionKeys;

    /// @notice Subscribe to an event on the Reactive Network
    /// @param contractAddress The contract emitting the event
    /// @param chainId The chain ID where the contract is deployed
    /// @param topic0 Event signature (keccak256 of event definition)
    /// @param topic1 Filter for indexed parameter 1 (0 = any)
    /// @param topic2 Filter for indexed parameter 2 (0 = any)
    /// @param topic3 Filter for indexed parameter 3 (0 = any)
    /// @param gasLimit Gas limit for callback execution
    /// @return success Always returns true for the mock
    function subscribe(
        address contractAddress,
        uint256 chainId,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3,
        uint256 gasLimit
    ) external returns (bool) {
        bytes32 key = keccak256(abi.encodePacked(contractAddress, chainId, topic0));

        if (subscriptions[key].originContract == address(0)) {
            subscriptionKeys.push(key);
        }

        subscriptions[key] = Subscription({
            originContract: contractAddress,
            chainId: chainId,
            topic0: topic0,
            topic1: topic1,
            topic2: topic2,
            topic3: topic3,
            gasLimit: gasLimit
        });

        emit SubscriptionRecorded(contractAddress, chainId, topic0, msg.sender);
        return true;
    }

    /// @notice Get all recorded subscriptions
    /// @return An array of all Subscription records
    function getSubscriptions() external view returns (Subscription[] memory) {
        Subscription[] memory result = new Subscription[](subscriptionKeys.length);
        for (uint256 i = 0; i < subscriptionKeys.length; i++) {
            result[i] = subscriptions[subscriptionKeys[i]];
        }
        return result;
    }

    /// @notice Get the count of subscriptions
    /// @return The number of subscriptions
    function getSubscriptionCount() external view returns (uint256) {
        return subscriptionKeys.length;
    }

    /// @notice Get a subscription by key (avoids struct tuple issue with public mapping)
    /// @param key The subscription key
    /// @return The Subscription struct
    function getSubscription(bytes32 key) external view returns (Subscription memory) {
        return subscriptions[key];
    }
}
