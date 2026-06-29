// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title CrossChainOracleDestination
/// @notice Destination contract deployed on Sepolia that receives price data
/// @dev Only the authorized callback proxy can call receivePrice()
contract CrossChainOracleDestination {
    /// @notice Sepolia Callback Proxy address for the Reactive Network
    address public constant CALLBACK_PROXY =
        0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    /// @notice Emitted when a price is received from the cross-chain oracle
    /// @param assetId Unique identifier for the asset
    /// @param price The price received
    /// @param timestamp The timestamp from the origin chain
    /// @param originTxOrigin The origin chain submitter (decoded from payload)
    event PriceReceived(
        bytes32 indexed assetId,
        uint256 price,
        uint256 timestamp,
        address indexed originTxOrigin
    );

    /// @notice Emitted when an unauthorized caller attempts to call receivePrice
    event UnauthorizedCaller(address indexed caller);

    /// @notice Mapping from assetId to latest received price
    mapping(bytes32 => uint256) public receivedPrices;

    /// @notice Mapping from assetId to receipt timestamp (destination chain time)
    mapping(bytes32 => uint256) public receiptTimestamps;

    /// @notice Receive a price update from the cross-chain oracle
    /// @dev Only callable by the CALLBACK_PROXY address
    /// @param assetId Unique identifier for the asset
    /// @param price The price from the origin chain
    /// @param timestamp The timestamp from the origin chain
    function receivePrice(
        bytes32 assetId,
        uint256 price,
        uint256 timestamp
    ) external {
        // Validate caller is the authorized callback proxy
        if (msg.sender != CALLBACK_PROXY) {
            emit UnauthorizedCaller(msg.sender);
            revert("Unauthorized: only callback proxy can call receivePrice");
        }

        require(price > 0, "Price must be greater than 0");
        require(timestamp > 0, "Timestamp must be greater than 0");

        receivedPrices[assetId] = price;
        receiptTimestamps[assetId] = block.timestamp;

        // The submitter address is encoded in the first 20 bytes of the
        // callback payload by the Reactive Network infrastructure.
        // Extract it from msg.data if needed (bytes 0-19 of calldata).
        address originTxOrigin;
        assembly {
            originTxOrigin := calldataload(0)
        }

        emit PriceReceived(assetId, price, timestamp, originTxOrigin);
    }

    /// @notice Get the received price for an asset
    /// @param assetId Unique identifier for the asset
    /// @return price The received price (0 if never received)
    function getReceivedPrice(bytes32 assetId) external view returns (uint256) {
        return receivedPrices[assetId];
    }

    /// @notice Get the receipt timestamp for an asset
    /// @param assetId Unique identifier for the asset
    /// @return timestamp The destination chain timestamp (0 if never received)
    function getReceiptTimestamp(
        bytes32 assetId
    ) external view returns (uint256) {
        return receiptTimestamps[assetId];
    }
}
