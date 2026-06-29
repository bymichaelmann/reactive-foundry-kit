// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title CrossChainOracleOrigin
/// @notice Origin contract deployed on Sepolia that emits PriceUpdated events
/// @dev This contract is the data source for the cross-chain oracle
contract CrossChainOracleOrigin {
    /// @notice Emitted when a price is updated
    /// @param submitter Address that submitted the price update
    /// @param assetId Unique identifier for the asset (e.g., keccak256("ETH/USD"))
    /// @param price Latest price for the asset (with 8 decimals like Chainlink)
    /// @param timestamp Block timestamp of the update
    event PriceUpdated(
        address indexed submitter,
        bytes32 indexed assetId,
        uint256 price,
        uint256 timestamp
    );

    /// @notice Mapping from assetId to latest price
    mapping(bytes32 => uint256) public latestPrices;

    /// @notice Mapping from assetId to last update timestamp
    mapping(bytes32 => uint256) public lastTimestamps;

    /// @notice Update the price for an asset
    /// @param assetId Unique identifier for the asset
    /// @param price Latest price for the asset
    function updatePrice(bytes32 assetId, uint256 price) external {
        require(price > 0, "Price must be greater than 0");

        latestPrices[assetId] = price;
        lastTimestamps[assetId] = block.timestamp;

        emit PriceUpdated(msg.sender, assetId, price, block.timestamp);
    }

    /// @notice Get the latest price for an asset
    /// @param assetId Unique identifier for the asset
    /// @return price Latest price (0 if never set)
    function getPrice(bytes32 assetId) external view returns (uint256) {
        return latestPrices[assetId];
    }

    /// @notice Get the last update timestamp for an asset
    /// @param assetId Unique identifier for the asset
    /// @return timestamp Last update timestamp (0 if never set)
    function getLastTimestamp(bytes32 assetId) external view returns (uint256) {
        return lastTimestamps[assetId];
    }
}
