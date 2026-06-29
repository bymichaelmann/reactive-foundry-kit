// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Log record structure passed to the react() callback
struct LogRecord {
    uint256 chainId;
    address _contract;
    uint256 topic0;
    uint256 topic1;
    uint256 topic2;
    uint256 topic3;
    bytes data;
}

/// @title IReactive Interface
/// @notice Interface for Reactive Network smart contracts
interface IReactive {
    /// @notice Emitted to trigger a callback on a destination chain
    /// @param chainId Destination chain ID
    /// @param _contract Destination contract address
    /// @param gasLimit Gas limit for the callback execution
    /// @param data Callback payload (first 160 bits replaced by deployer address)
    event Callback(uint256 chainId, address _contract, uint256 indexed gasLimit, bytes data);

    /// @notice Called by the Reactive Network when a subscribed event is emitted
    /// @param log The log record containing the event data
    function react(LogRecord memory log) external;
}

/// @title ISubscriptionProxy Interface
/// @notice Interface for subscribing to events on the Reactive Network
interface ISubscriptionProxy {
    /// @notice Subscribe to an event
    /// @param contractAddress The contract emitting the event
    /// @param chainId The chain ID where the contract is deployed
    /// @param topic0 Event signature (keccak256 of event definition)
    /// @param topic1 Filter for indexed parameter 1 (0 = any)
    /// @param topic2 Filter for indexed parameter 2 (0 = any)
    /// @param topic3 Filter for indexed parameter 3 (0 = any)
    /// @param gasLimit Gas limit for callback execution
    /// @return success Whether the subscription was successful
    function subscribe(
        address contractAddress,
        uint256 chainId,
        uint256 topic0,
        uint256 topic1,
        uint256 topic2,
        uint256 topic3,
        uint256 gasLimit
    ) external returns (bool);
}
