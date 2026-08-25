# vmp-ci-shim

Reusable GitHub Actions workflow templates for ARM64 Rust projects. Targets
`ubuntu-24.04-arm` hosted runners with optional Termux/bionic libc parity
validation.

## CI layers

The `CI` workflow is dispatched with a full 40-character private-repository
commit SHA. The default `all` layer starts independent jobs in parallel:

- `public_demo`: public example smoke test
- `glibc_unit` / `bionic_unit`: workspace library and binary unit tests only
- `glibc_e2e` / `bionic_e2e`: EH fixture plus all realib suites, split into
  independently scheduled shards (up to four ARM runners per libc)

Use `layer=unit` for fast Rust-only validation or `layer=e2e` when the unit
cache is already warm. The `e2e_instances` input selects 1, 2, or 4 runner
shards. The four-way layout assigns small realib suites, yaml/protobuf suites,
`cpp_business`, and the matrix suite separately; each shard builds only its
own Cargo test targets. Realib fixture runs use isolated temporary copies and
can use bounded in-process test threads without clobbering sibling shards.
The runner builds each selected test target once with `--no-run` and executes
the resulting test binary directly; it does not first compile the entire
workspace and then precompile the same targets again.

Failed checkout, proxy, or toolchain setup stops that job immediately. Logs and
diagnostics are uploaded only when they exist, so setup failures do not create
secondary artifact failures or fake suite failures.

## Usage

Trigger via `workflow_dispatch` with inputs:

| Input | Description |
|-------|-------------|
| `commit_sha` | Required full 40-character SHA from the private source repository |
| `branch` | Branch name for notification context only |
| `layer` | `all`, `unit`, or `e2e`; defaults to `all` |
| `e2e_instances` | `1`, `2`, or `4` independent E2E runners; defaults to `2` |
| `oracle_litmus` | Optional Cat 2B differential-oracle litmus on bionic (shard 0 only) |

Requires secrets:

- `PRIVATE_REPO_URL` — Git URL of the source repository
- `DEPLOY_KEY` — SSH private key with read access
- `TELEGRAM_BOT_TOKEN` — Bot token for failure notifications
- `TELEGRAM_CHAT_ID` — Target Telegram chat

## License

MIT
