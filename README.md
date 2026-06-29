# Reactive Foundry Kit (rfk)

[![MIT License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![CI](https://github.com/user/reactive-foundry-kit/workflows/Test/badge.svg)](https://github.com/user/reactive-foundry-kit/actions)

A batteries-included Foundry test harness for **Reactive Smart Contracts (RSCs)**. Simulate the full event → `react()` → callback → destination loop **locally, offline, with no testnet deploy**.

```solidity
// Instead of manually constructing LogRecords and checking event emissions,
// you can now write forge tests that assert on DESTINATION STATE.
emitAndReact(address(origin), address(reactive));
deliverCallbacks(address(reactive), address(destination), address(0));
assertEq(destination.getReceivedValue(key), expectedValue);
```

## Why this exists

Reactive Smart Contracts are uniquely hard to test:

- **`react()` is infra-invoked** — there is no way to trigger it in a normal Forge test without manually constructing LogRecord structs over and over.
- **The callback payload has a quirky 20-byte deployer substitution** — the RN infrastructure replaces the first 160 bits of the callback data with the deployer's address for authentication.
- **Subscriptions are out-of-band** — in RNK mode, constructor `subscribe()` calls work; in RVM mode, they're skipped. Testing both modes means duplicating test setup.
- **The full loop only happens on testnet deploy** — debugging a failed callback means deploying 3+ contracts and troubleshooting RPC issues, not `forge test`.

rfk solves all of this with a single `ReactiveHarness` base contract.

## Quickstart

### 1. Install

```bash
forge install Reactive-Network/reactive-smart-contract-demos  # or
git submodule add <rfk-repo-url> lib/rfk
```

Add remappings to `foundry.toml`:

```toml
remappings = ["rfk/=lib/rfk/src/"]
```

### 2. Write a test

```solidity
import {ReactiveHarness} from "rfk/ReactiveHarness.sol";
import {ReactiveRegistry} from "rfk/ReactiveRegistry.sol";

contract MyTest is ReactiveHarness {
    // ... deploy your Origin, Reactive, and Destination contracts in setUp()

    function test_FullLoop() public {
        vm.chainId(ORIGIN_CHAIN_ID);

        // 1. Emit an event on the origin contract
        vm.recordLogs();
        origin.updateData(key, 42);

        // 2. Process it through the reactive contract
        vm.chainId(RSC_CHAIN_ID);
        emitAndReact(address(origin), address(reactive));

        // 3. Deliver callbacks to the destination
        deliverCallbacks(address(reactive), address(destination), address(0));

        // 4. Assert on DESTINATION STATE — the key rfk value prop
        assertEq(destination.getReceivedValue(key), 42);
    }
}
```

### 3. Run tests

```bash
forge test -vvv
```

## Architecture

```
lib/rfk/
├── src/
│   ├── ReactiveHarness.sol     — Main test harness (extends forge-std Test)
│   ├── ReactiveRegistry.sol     — Multi-chain address registry
│   └── mocks/
│       ├── MockSystemContract.sol     — Mock subscription system
│       ├── MockSubscriptionProxy.sol  — Mock subscription proxy
│       └── MockCallbackProxy.sol      — Mock callback executor
├── test/
│   ├── ReactiveOracleE2ETest.t.sol    — Golden e2e example
│   └── ReactiveHarnessUnitTest.t.sol  — Harness unit tests
├── examples/
│   ├── CrossChainOracleOrigin.sol
│   ├── CrossChainOracleDestination.sol
│   └── CrossChainOracleReactive.sol
├── script/
│   └── new-rsc.sh              — Scaffolding generator
└── README.md
```

## API Reference

### ReactiveHarness

Extends forge-std `Test`. Provides:

| Function | Description |
|----------|-------------|
| `setUp()` | Deploys mock system/subscription/callback proxies |
| `emitAndReact(address origin, address rsc)` | Captures recorded logs and delivers them to `rsc.react()` as LogRecords |
| `deliverCallbacks(address rsc, address dest, address expectedDeployer)` | Captures Callback events, verifies deployer substitution, executes calls against destination |
| `assertSubscriptionRecorded(address origin, uint256 chainId, bytes32 topic0)` | Verifies a subscription was registered |
| `assertCallbackEmitted(address dest, bytes4 selector)` | Verifies a Callback was emitted for a specific destination/selector |
| `setRscMode(RscMode mode)` | Toggle between RNK and RVM mode |
| `enableDebug()` / `disableDebug()` | Enable/disable decoded debug output including LogRecord and Callback details |

### ReactiveRegistry

Canonical chain configuration:

| Function | Description |
|----------|-------------|
| `getChainConfig(uint256 chainId)` | Full chain config (chainId, name, callbackProxy, systemContract, subscriptionProxy) |
| `getCallbackProxy(uint256 chainId)` | Callback proxy address for a chain |
| `getSystemContract(uint256 chainId)` | System contract address |
| `getSubscriptionProxy(uint256 chainId)` | Subscription proxy address |
| `supportedChains()` | Array of all supported chain configs |

Supported chains: Sepolia (11155111), Lasna (5318007).

### RNK vs RVM modes

- **RNK** (default): subscription proxy is available; constructor `subscribe()` calls connect to the mock system contract.
- **RVM**: subscription proxy returns `address(0)`; constructor `subscribe()` calls are gracefully skipped (try/catch) as in the live RVM environment.

```solidity
function test_BothModes() public {
    // Default: RNK
    assertTrue(isRnkMode());
    assertTrue(getSubscriptionProxyAddress() != address(0));

    setRscMode(RscMode.RVM);
    assertTrue(isRvmMode());
    assertEq(getSubscriptionProxyAddress(), address(0));
}
```

### Debug mode

Enable decoded output from `emitAndReact` and `deliverCallbacks`:

```solidity
enableDebug();
emitAndReact(address(origin), address(reactive));
// Console output:
// emitAndReact: processing 1 logs from originContract 0x...
//   -> LogRecord(chainId=11155111, contract=0x..., topic0=0x..., ...)
```

## Example: Cross-Chain Oracle

The `examples/` directory contains a complete cross-chain oracle dApp ported from the Reactive Network bounty demo:

- **Origin** (`CrossChainOracleOrigin.sol`): emits `PriceUpdated` events on Sepolia
- **Reactive** (`CrossChainOracleReactive.sol`): monitors events from origin, relays significant (>0.5%) price changes via callback
- **Destination** (`CrossChainOracleDestination.sol`): receives price data only from the authorized callback proxy

The 16 tests in `test/ReactiveOracleE2ETest.t.sol` demonstrate the full harness API including the complete integration test that asserts on destination state.

## Scaffolding Generator

Create a new RSC project from templates:

```bash
./script/new-rsc.sh my-oracle 11155111 11155111
cd my-oracle
forge test -vvv
```

This generates a complete project with Origin, Reactive, Destination contracts and a test file that exercises the full loop.

## Comparison with reactive-lib and reactive-test-lib

| Feature | reactive-lib | reactive-test-lib | **rfk** |
|---------|-------------|-------------------|---------|
| Interfaces (IReactive, ISubscriptionProxy) | ✅ | ✅ | ✅ (reuses) |
| Abstract contracts (AbstractReactive, AbstractCallback) | ✅ | — | — (higher-level) |
| Mock system contract | — | ✅ | ✅ |
| Full-loop driver (emit → react → callback → destination) | — | — | ✅ |
| Multi-chain address registry | — | — | ✅ |
| RNK/RVM mode toggles | — | — | ✅ |
| Debug/decoded callback printing | — | — | ✅ |
| Scaffolding generator | — | — | ✅ |
| Golden e2e example | — | — | ✅ |

rfk builds **on top of** reactive-lib and reactive-test-lib — it differentiates where they stop: closing the full testing loop and providing developer tooling.

## License

MIT © Michael Mann <michaelmann@disroot.org>
