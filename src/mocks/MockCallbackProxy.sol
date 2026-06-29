// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Information about the last callback execution
struct CallbackInfo {
    address targetContract;
    bytes data;
    uint256 gasLimit;
    bool executed;
    bool success;
    bytes returnData;
}

/// @title MockCallbackProxy
/// @notice A mock of the Reactive Network callback proxy for testing
/// @dev Simulates callback delivery by executing arbitrary calls
contract MockCallbackProxy {
    /// @notice Information about the last callback execution
    CallbackInfo public lastCallback;

    /// @notice Emitted when a callback is executed
    /// @param targetContract The contract called
    /// @param success Whether the call succeeded
    /// @param returnData The return data from the call
    event CallbackExecuted(address indexed targetContract, bool success, bytes returnData);

    /// @notice Execute a callback to a destination contract
    /// @dev The first 20 bytes of `data` are the deployer address (substituted by RN infra)
    /// @param _contract The destination contract address
    /// @param data The callback payload (first 20 bytes = deployer address, rest = calldata)
    /// @param gasLimit Gas limit for the execution
    /// @return success Whether the call succeeded
    function executeCallback(address _contract, bytes calldata data, uint256 gasLimit) external returns (bool) {
        require(data.length >= 20, "MockCallbackProxy: data too short");

        // The first 20 bytes are the deployer address
        address deployer;
        assembly {
            deployer := calldataload(data.offset)
        }

        // The remaining bytes are the actual calldata (function selector + args)
        bytes memory callData = new bytes(data.length - 20);
        for (uint256 i = 20; i < data.length; i++) {
            callData[i - 20] = data[i];
        }

        // Execute the call with the deployer as the origin (simulated prank)
        (bool success, bytes memory returnData) = _contract.call{gas: gasLimit}(callData);

        lastCallback = CallbackInfo({
            targetContract: _contract,
            data: data,
            gasLimit: gasLimit,
            executed: true,
            success: success,
            returnData: returnData
        });

        emit CallbackExecuted(_contract, success, returnData);

        if (!success) {
            // Revert with the same reason so tests can catch it
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        return success;
    }

    /// @notice Get the deployer address from callback data
    /// @param data The callback payload
    /// @return deployer The deployer address (first 20 bytes)
    function extractDeployer(bytes calldata data) external pure returns (address) {
        require(data.length >= 20, "MockCallbackProxy: data too short");
        address deployer;
        assembly {
            deployer := calldataload(data.offset)
        }
        return deployer;
    }

    /// @notice Get the function selector from callback data
    /// @param data The callback payload
    /// @return selector The 4-byte function selector
    function extractSelector(bytes calldata data) external pure returns (bytes4) {
        require(data.length >= 24, "MockCallbackProxy: data too short for selector");
        bytes4 selector;
        assembly {
            selector := calldataload(add(data.offset, 20))
        }
        return selector;
    }
}
