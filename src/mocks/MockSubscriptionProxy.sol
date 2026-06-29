// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscriptionProxy} from "@reactive-lib/IReactive.sol";
import {MockSystemContract} from "./MockSystemContract.sol";

/// @title MockSubscriptionProxy
/// @notice A mock of the Reactive Network subscription proxy for testing
/// @dev Delegates subscribe() calls to MockSystemContract
contract MockSubscriptionProxy {
    /// @notice Reference to the mock system contract
    MockSystemContract public systemContract;

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
        return systemContract.subscribe(
            contractAddress,
            chainId,
            topic0,
            topic1,
            topic2,
            topic3,
            gasLimit
        );
    }

    /// @notice Set the system contract reference
    /// @param _systemContract Address of the MockSystemContract
    function setSystemContract(address _systemContract) external {
        systemContract = MockSystemContract(_systemContract);
    }
}
