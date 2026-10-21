# Super Fren Pet tests

The expected supply is `10^27` smallest units: one billion SFP with 18 decimals.
All tests deploy the real `SuperFrenPet` contract and exercise its public API.

| Suite | Coverage |
| --- | --- |
| `SuperFrenPet.t.sol` | Existing metadata, constructor mint/event, immediate deployer and CREATE2 factory allocation, exact token-side launch flows, transfers, approvals, unauthorized calls, and four fuzz properties. |
| `SuperFrenPet.edges.t.sol` | One-unit and maximum-value boundaries, overlapping caller/source/recipient roles, approval replacement and isolation, repeated spending, failed-call rollback, and transfers through a contract without a receiver hook. Six fuzz properties run 1,000 cases each. |
| `SuperFrenPet.invariant.t.sol` | 256 random sequences of 128 handler calls, checking conservation and every tracked balance and allowance after each call. |

The invariant uses four funded actors, including self-transfers and self-approvals.
Its eight targeted actions mix transfers, approvals, revocation, delegated
transfers, insufficient balances, insufficient allowances, and zero recipients.
Each actor starts with a finite approval to another actor so successful delegated
transfers are reachable from the start.

Expected balances and all 16 owner/spender allowances are recorded independently
from the token's getters. Successful operations update this ledger; rejected
operations leave it unchanged. Each invariant check compares the complete ledger
with the token and checks that balances sum to the fixed supply. This also checks
that operations leave unrelated accounts and allowances unchanged. Expected
rejections assert their specific custom errors; unexpected handler reverts fail
the campaign. Only the eight action selectors are fuzz targets.

New fuzz cases use bounded inputs without discarded assumptions. The suite uses
no forks, FFI, environment changes, downloaded dependencies, or storage edits.
Known zero, one-unit, full-supply, and maximum-value cases are pinned by unit tests.

Run the build and all tests with the verifier's seed:

```sh
forge build --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0xb86c56f565f41b6d38425645a0884e12c6f3882d10e7962f918854067ae37ca1 forge test --out test/scratch/out --cache-path test/scratch/cache
```

The output/cache flags keep generated artifacts in the disposable scratch area;
no delivered test imports anything from it. Ordinary `forge build` and
`forge test` also use the same tests and inline run counts.

The supplied protected checks were reviewed. Their external factory/Uniswap v4
harness and launch configuration are absent from this repository, so local
token-side flow tests do not claim to execute actual pool initialization or swaps.
