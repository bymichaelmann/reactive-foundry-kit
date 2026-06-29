// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Chain configuration for the Reactive Network
struct ChainConfig {
    uint256 chainId;
    string name;
    address callbackProxy;
    address systemContract;
    address subscriptionProxy;
}

/// @title ReactiveRegistry
/// @notice Canonical chain configuration library for the Reactive Network
/// @dev Provides chain-specific addresses for callback proxy, system contract,
///      and subscription proxy. Extend by adding entries to `_getChainConfigs()`.
library ReactiveRegistry {
    // -----------------------------------------------------------------------
    // Canonical addresses from Reactive Network documentation
    // -----------------------------------------------------------------------

    /// @notice Sepolia callback proxy address
    address public constant SEPOLIA_CALLBACK_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    /// @notice Sepolia chain ID
    uint256 public constant SEPOLIA_CHAIN_ID = 11_155_111;

    /// @notice Sepolia system contract address (TBD - update when documented)
    address public constant SEPOLIA_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000000000;

    /// @notice Sepolia subscription proxy address (TBD - update when documented)
    address public constant SEPOLIA_SUBSCRIPTION_PROXY = 0x0000000000000000000000000000000000000000;

    /// @notice Lasna chain ID
    uint256 public constant LASNA_CHAIN_ID = 5_318_007;

    /// @notice Lasna callback proxy address (same as Sepolia as per docs)
    address public constant LASNA_CALLBACK_PROXY = 0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA;

    /// @notice Lasna system contract address (TBD)
    address public constant LASNA_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000000000;

    /// @notice Lasna subscription proxy address (TBD)
    address public constant LASNA_SUBSCRIPTION_PROXY = 0x0000000000000000000000000000000000000000;

    // -----------------------------------------------------------------------
    // Internal configuration
    // -----------------------------------------------------------------------

    /// @notice Internal function returning all known chain configurations
    /// @return configs Array of ChainConfig
    function _getChainConfigs() internal pure returns (ChainConfig[2] memory configs) {
        configs[0] = ChainConfig({
            chainId: SEPOLIA_CHAIN_ID,
            name: "Sepolia",
            callbackProxy: SEPOLIA_CALLBACK_PROXY,
            systemContract: SEPOLIA_SYSTEM_CONTRACT,
            subscriptionProxy: SEPOLIA_SUBSCRIPTION_PROXY
        });

        configs[1] = ChainConfig({
            chainId: LASNA_CHAIN_ID,
            name: "Lasna",
            callbackProxy: LASNA_CALLBACK_PROXY,
            systemContract: LASNA_SYSTEM_CONTRACT,
            subscriptionProxy: LASNA_SUBSCRIPTION_PROXY
        });
    }

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    /// @notice Get the chain configuration for a given chain ID
    /// @param chainId The chain ID to look up
    /// @return The ChainConfig struct for the chain
    function getChainConfig(uint256 chainId) internal pure returns (ChainConfig memory) {
        ChainConfig[2] memory configs = _getChainConfigs();
        for (uint256 i = 0; i < configs.length; i++) {
            if (configs[i].chainId == chainId) {
                return configs[i];
            }
        }
        revert("ReactiveRegistry: unknown chain ID");
    }

    /// @notice Get the callback proxy address for a chain
    /// @param chainId The chain ID
    /// @return The callback proxy address
    function getCallbackProxy(uint256 chainId) internal pure returns (address) {
        return getChainConfig(chainId).callbackProxy;
    }

    /// @notice Get the system contract address for a chain
    /// @param chainId The chain ID
    /// @return The system contract address
    function getSystemContract(uint256 chainId) internal pure returns (address) {
        return getChainConfig(chainId).systemContract;
    }

    /// @notice Get the subscription proxy address for a chain
    /// @param chainId The chain ID
    /// @return The subscription proxy address
    function getSubscriptionProxy(uint256 chainId) internal pure returns (address) {
        return getChainConfig(chainId).subscriptionProxy;
    }

    /// @notice Get all supported chain configurations
    /// @return An array of all ChainConfig structs
    function supportedChains() internal pure returns (ChainConfig[] memory) {
        ChainConfig[2] memory configs = _getChainConfigs();
        ChainConfig[] memory result = new ChainConfig[](configs.length);
        for (uint256 i = 0; i < configs.length; i++) {
            result[i] = configs[i];
        }
        return result;
    }

    /// @notice Wire up a test with the correct chain configuration
    /// @dev Helper for tests: returns the ChainConfig for Sepolia (default test chain)
    /// @return The ChainConfig for Sepolia
    function wireTest(
        address,
        /* originContract */
        address /* destinationContract */
    )
        internal
        pure
        returns (ChainConfig memory)
    {
        // Default to Sepolia for tests
        return getChainConfig(SEPOLIA_CHAIN_ID);
    }
}
