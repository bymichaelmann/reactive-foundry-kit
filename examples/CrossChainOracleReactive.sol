// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IReactive, LogRecord, ISubscriptionProxy} from "@reactive-lib/IReactive.sol";

/// @title CrossChainOracleReactive
/// @notice Reactive contract deployed on Reactive Lasna Testnet
/// @dev Monitors PriceUpdated events from origin and relays to destination via callbacks
///      Runs in both RNK (EOA accessible) and RVM (private) environments
contract CrossChainOracleReactive is IReactive {
    /// @notice The origin contract address (on Sepolia)
    address public immutable ORIGIN_CONTRACT;

    /// @notice The origin chain ID (Sepolia = 11155111)
    uint256 public immutable ORIGIN_CHAIN_ID;

    /// @notice The destination contract address (on Sepolia)
    address public immutable DESTINATION_CONTRACT;

    /// @notice The destination chain ID (Sepolia = 11155111)
    uint256 public immutable DESTINATION_CHAIN_ID;

    /// @notice Event signature hash for PriceUpdated
    bytes32 public constant PRICE_UPDATED_TOPIC_0 =
        keccak256("PriceUpdated(address,bytes32,uint256,uint256)");

    /// @notice Gas limit for callback execution on destination
    uint256 public constant CALLBACK_GAS_LIMIT = 200_000;

    /// @notice Threshold for price change (0.5% = 50 basis points)
    uint256 public constant PRICE_CHANGE_BASIS_POINTS = 50;

    /// @notice Basis points denominator (100% = 10000 bps)
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10000;

    /// @notice Mapping from assetId to last relayed price
    /// @dev Used to detect significant price changes
    mapping(bytes32 => uint256) public lastRelayedPrices;

    /// @notice Emitted when a price update is received from origin
    /// @param assetId The asset identifier
    /// @param price The new price
    /// @param timestamp The timestamp from origin
    /// @param submitter The address that submitted the price
    /// @param relayed Whether the price was relayed to destination
    event PriceUpdateReceived(
        bytes32 indexed assetId,
        uint256 price,
        uint256 timestamp,
        address indexed submitter,
        bool relayed
    );

    /// @notice Emitted when subscription fails (expected in RVM environment)
    event SubscriptionError(string reason);

    /// @notice Constructor subscribes to PriceUpdated events on the origin chain
    /// @param _originContract Address of the origin contract on Sepolia
    /// @param _originChainId Chain ID where origin is deployed
    /// @param _destinationContract Address of the destination contract on Sepolia
    /// @param _destinationChainId Chain ID where destination is deployed
    /// @param _subscriptionProxy Address of the subscription proxy
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

        // Attempt subscription - works in RNK, may fail in RVM
        // Both environments must be handled gracefully
        if (_subscriptionProxy != address(0)) {
            try
                ISubscriptionProxy(_subscriptionProxy).subscribe(
                    _originContract,
                    _originChainId,
                    uint256(PRICE_UPDATED_TOPIC_0),
                    0, // topic1 filter (any)
                    0, // topic2 filter (any)
                    0, // topic3 filter (any)
                    CALLBACK_GAS_LIMIT
                )
            returns (bool success) {
                if (!success) {
                    emit SubscriptionError("Subscription returned false");
                }
            } catch Error(string memory reason) {
                emit SubscriptionError(reason);
            } catch (bytes memory lowLevelData) {
                emit SubscriptionError(
                    string(
                        abi.encodePacked(
                            "Subscription failed: ",
                            lowLevelData
                        )
                    )
                );
            }
        } else {
            emit SubscriptionError("No subscription proxy provided");
        }
    }

    /// @notice React to a subscribed event
    /// @dev Called by the Reactive Network when PriceUpdated is emitted
    /// @param log The log record containing event data
    function react(LogRecord memory log) external override {
        // Only process events from our subscribed origin contract and chain
        if (log._contract != ORIGIN_CONTRACT || log.chainId != ORIGIN_CHAIN_ID) {
            return;
        }

        // Verify this is the PriceUpdated event
        if (log.topic0 != uint256(PRICE_UPDATED_TOPIC_0)) {
            return;
        }

        // Decode indexed parameters
        // topic1 = submitter (address, left-padded to 32 bytes)
        // topic2 = assetId (bytes32)
        address submitter = address(uint160(log.topic1));
        bytes32 assetId = bytes32(log.topic2);

        // Decode non-indexed parameters from log.data
        // data = abi.encode(price, timestamp)
        (uint256 price, uint256 timestamp) = abi.decode(
            log.data,
            (uint256, uint256)
        );

        require(price > 0, "Price must be greater than 0");
        require(timestamp > 0, "Timestamp must be greater than 0");

        // Check if price changed significantly (>0.5%)
        uint256 lastPrice = lastRelayedPrices[assetId];
        bool shouldRelay = false;

        if (lastPrice == 0) {
            // First price for this asset - always relay
            shouldRelay = true;
        } else {
            // Calculate percentage change in basis points
            uint256 changeBps;
            if (price > lastPrice) {
                // Price increased
                changeBps = ((price - lastPrice) * BASIS_POINTS_DENOMINATOR) / lastPrice;
            } else {
                // Price decreased
                changeBps = ((lastPrice - price) * BASIS_POINTS_DENOMINATOR) / lastPrice;
            }

            // Relay if change exceeds threshold
            if (changeBps >= PRICE_CHANGE_BASIS_POINTS) {
                shouldRelay = true;
            }
        }

        if (shouldRelay) {
            // Update stored price
            lastRelayedPrices[assetId] = price;

            // Prepare callback payload
            // First 20 bytes: placeholder for deployer address (will be replaced by RN infrastructure)
            // Remaining bytes: abi encoded function call to receivePrice(bytes32,uint256,uint256)
            bytes memory payload = abi.encodePacked(
                address(0), // 20 bytes - replaced by deployer address for auth
                abi.encodeWithSelector(
                    bytes4(keccak256("receivePrice(bytes32,uint256,uint256)")),
                    assetId,
                    price,
                    timestamp
                )
            );

            // Emit callback event
            emit Callback(
                DESTINATION_CHAIN_ID,
                DESTINATION_CONTRACT,
                CALLBACK_GAS_LIMIT,
                payload
            );
        }

        emit PriceUpdateReceived(
            assetId,
            price,
            timestamp,
            submitter,
            shouldRelay
        );
    }
}
