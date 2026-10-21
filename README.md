# Super Fren Pet (SFP)

`src/SuperFrenPet.sol:SuperFrenPet` is a fixed-supply ERC-20 token. Its only custom
logic sets the metadata and mints the entire supply to `msg.sender` in the
constructor. ERC-20 behavior comes from the vendored OpenZeppelin Contracts
v5.0.2 implementation.

| Property | Value |
| --- | --- |
| Solidity contract | `SuperFrenPet` |
| Token name | `Super Fren Pet` |
| Symbol | `SFP` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Initial recipient | Immediate deployer (`msg.sender`) |
| Native currency needed by constructor | None; constructor is nonpayable |
| Owner / administrator / upgrade authority | None |

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xb86c56f565f41b6d38425645a0884e12c6f3882d10e7962f918854067ae37ca1 forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimizer enabled
with 200 runs, and `bytecode_hash = "none"`. Dependencies are ordinary source
files in `lib/`; no dependency download, submodule, FFI, filesystem permission,
RPC endpoint, wallet, or environment configuration is needed to build or test.
The seed above controls Foundry's test runner; the tests themselves do not read
or modify environment variables. The compiler must already be installed for an
offline build.

The suite checks metadata and exact minting (including the mint event), EOA and
CREATE2 factory deployment, launch distribution and token-side settlement,
transfer and approval events, zero/self/full-balance transfers, finite and
infinite allowances, revocation, unauthorized spending, insufficient balances,
invalid recipients, and atomic rollback on failure. It also checks that common
mint, burn, owner, freeze, seizure, and upgrade calls revert. Four fuzz tests run
512 cases each. A stateful invariant executes 128 sequences of up to 64 calls,
checking balances and allowances after actions and conservation of the complete
supply across its closed set of holders.

The supplied protected tests describe an external launch harness that includes
the actual Uniswap v4 PoolManager, factory inputs, and owner checks. That harness
and its launch configuration are not part of this repository. Local tests cover
the token's exact transfers through equivalent roles; they do not claim to run
the protected suite or execute actual swaps.

## Assumptions and transfer behavior

- The requested token uses standard ERC-20 semantics. No tax, transfer fee,
  rebasing, burn extension, permit, pause, blacklist, or upgrade mechanism is
  added. No application contracts are required.
- `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` is fixed in the source. The only
  reachable mint is in the constructor. No external function can mint or burn.
- All amounts passed to the token are integers in smallest units: one SFP is
  `10^18` units. Successful transfers deliver exactly the requested amount and
  return `true`; invalid actions revert with OpenZeppelin ERC-20 custom errors.
- Transfers of zero to a nonzero address are valid and emit `Transfer`.
  Self-transfers preserve balances. Transfers to the zero address and approvals
  to the zero spender revert.
- `approve` replaces the caller's allowance for one spender. `transferFrom`
  consumes finite allowance, even when the spender is the source account or
  source and destination are identical. The maximum `uint256` allowance remains
  unchanged when spent. A zero-value `transferFrom` between valid addresses is
  permitted without a positive allowance.
- Explicit approvals emit `Approval`. In this OpenZeppelin version, spending an
  allowance does not emit another `Approval`; integrations should query
  `allowance()` for its current value.
- Transfers do not call recipient contracts, oracles, routers, or any other
  external contract. No receiver callback is required.

## Deployment parameters and launch responsibilities

The target launch is Ethereum (chain ID 1). Deploy the compiled creation bytecode
of `SuperFrenPet` directly with no constructor arguments and no native value.
There are no linked libraries or initialization calls. Do not deploy this token
behind a proxy: the supply is created by its constructor.

The immediate deploying account receives all `10^27` units. In the IdentityMD
launch this is the launch factory, even when a separate wallet initiates the
transaction. `tx.origin` has no role in the allocation. A direct EOA deployment
would instead allocate everything to that EOA. The token makes no external
constructor calls and requires no pre-existing contract addresses.

The factory, outside this token, distributes the launch supply: 10% to the
launch's MerkleDistributor, 80% toward pool seeding, and the remaining 10% to
the requester recipient specified in the assignment. These shares are not
reserved or transferred by the token constructor. Neither the token nor a
local test harness manages a pool, calculates its price, or claims to perform
the launch. The separate manifest step supplies the provided pool/economics
settings and produces `launch.json`; this project needs no launch addresses as
constructor parameters.

The network deployer is responsible for preparing and validating the manifest,
factory deployment, distribution, pool setup, source verification, and checking
the deployed metadata, total supply, and mint recipient. This assignment
produces source and local verification only; it does not broadcast transactions
or use wallet keys.

## After launch

There are no owner settings, roles to transfer, configuration transactions,
keepers, or minting responsibilities. Holders control their own balances and
approvals. The deployer has no special power over holder balances after
distribution.

Holders and integrations must check recipient addresses and spender contracts.
Prefer finite approvals and revoke unused allowances. When changing an existing
nonzero allowance, account for the standard ERC-20 approval transaction-ordering
race (for example, confirm revocation before granting the replacement). A
maximum allowance authorizes spending future receipts too, until revoked.

The contract has no asset recovery function. SFP sent to the token contract or
another address without a way to transfer it can become inaccessible. Native
currency is not accepted through ordinary calls, and forcibly delivered native
currency cannot be recovered by this contract. There is no administrator to
reverse mistaken transfers or patch the deployed bytecode.

## Security review scope

The local review considers fixed supply, exact accounting, allowance isolation,
failure atomicity, constructor recipient, absence of administrative paths, and
absence of external calls. The requested functionality does not use prices,
randomness, signatures, vault shares, or upgradeable storage. The security
reference supplied with the assignment was used as background for that review.

Foundry unit, fuzz, and stateful invariant tests are provided. Slither and
Mythril are not part of the recorded checks. These checks are not an independent
security audit; the network's independent review and full protected launch
checks remain release responsibilities.

See [DEPENDENCIES.md](DEPENDENCIES.md) for vendored versions and licenses.

