# vmp-ci-shim

Reusable GitHub Actions workflow templates for ARM64 Rust projects. Targets
`ubuntu-24.04-arm` hosted runners with optional Termux/bionic libc parity
validation via Docker.

## Features

- Native ARM64 hosted runner (no qemu, no cross)
- Optional second job inside `termux/termux-docker` to validate bionic libc compatibility
- Hard gates every realib e2e suite on both glibc and bionic, including New V6 coverage
- Telegram bot integration for failure notifications
- Designed for projects that maintain separate development and CI repositories

## Usage

Trigger via `workflow_dispatch` with inputs:

| Input         | Description                            |
|---------------|----------------------------------------|
| `commit_sha`  | Commit SHA to test (required)          |
| `branch`      | Branch name for context (optional)     |

Requires secrets:
- `PRIVATE_REPO_URL` — Git URL of the source repository
- `DEPLOY_KEY` — SSH private key with read access
- `TELEGRAM_BOT_TOKEN` — Bot token for failure notifications
- `TELEGRAM_CHAT_ID` — Target chat ID

## License

MIT
