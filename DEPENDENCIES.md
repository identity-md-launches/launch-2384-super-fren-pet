# Vendored dependencies

All necessary dependency source files are included as regular files. There are
no package-manager install steps, submodules, or dynamically fetched imports.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2) | `v5.0.2` | `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`, `Context.sol`, `draft-IERC6093.sol` | [MIT](lib/openzeppelin-contracts/LICENSE) |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Upstream Solidity files in `src/`, used only by tests | [MIT](lib/forge-std/LICENSE-MIT) or [Apache-2.0](lib/forge-std/LICENSE-APACHE) |

OpenZeppelin files were retrieved from
`https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v5.0.2/`.
Forge Standard Library files were retrieved from
`https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`.
Only the listed sources and their upstream licenses were retained. No upstream
project configuration, scripts, tests, or Git metadata is required.

The files are unmodified copies. From the root of this project, verify the
vendored contents with:

```sh
sha256sum -c lib/SHA256SUMS
```

The remappings in `foundry.toml` resolve both dependencies inside this repository.
Only OpenZeppelin's ERC-20 and its internal helpers contribute to the production
token bytecode. The testing library does not ship in the token.
