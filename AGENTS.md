# Agent Instructions

## Repository Setup

**Working Repository**: `https://github.com/llm-at-cormora/nornnet-public`
- All development work takes place here
- This is the `origin` remote

**Governance Repository**: `https://github.com/OS2sandbox/nornnet`
- Governance-only repo (for org policies, issues, discussions)
- Not used for development

## GitHub Credentials

Credentials are stored in `.env` (see `.env` file for `GITHUB_TOKEN`).
- Token scope: `llm-at-cormora` account
- All pushes go to `llm-at-cormora/nornnet-public`

## Remote Testing Infrastructure (Hetzner)

### Build Server (for running tests)
- **Host**: `46.224.173.88` (nornnet-build-temp)
- **Purpose**: Run acceptance tests, build bootc images
- **Tools**: podman, git, bats
- **SSH**: `ssh -i ~/.ssh/hetzner_ed25519 root@46.224.173.88`

### Bootc Device (for device deployment tests)
- **Host**: `46.224.174.46` (nornnet-bootc)
- **Purpose**: Dedicated bootc-managed server for testing US4/US5
- **Status**: Properly booted via bootc (running `quay.io/fedora/fedora-bootc:42`)
- **SSH**: `ssh -i ~/.ssh/hetzner_ed25519 root@46.224.174.46`

### Environment Variables for Testing

```bash
# Bootc device configuration
export BOOTC_DEVICE_HOST=46.224.174.46
export BOOTC_DEVICE_SSH_KEY=~/.ssh/hetzner_ed25519

# Build/test server (where tests run)
export HETZNER_SERVER_IP=46.224.173.88
export DEVICE_SSH_KEY=~/.ssh/hetzner_ed25519
```

### Running Tests

```bash
# SSH to build server with keys
ssh -i ~/.ssh/hetzner_ed25519 root@46.224.173.88

# On build server:
export BOOTC_DEVICE_HOST=46.224.174.46
export BOOTC_DEVICE_SSH_KEY=/root/.ssh/hetzner_ed25519
cd /root/nornnet
git pull origin main
bats tests/acceptance/
```

### Hetzner API Credentials (stored in `.env`)
- `HETZNER_API_TOKEN` - Hetzner API token
- `HETZNER_SERVER_SSH_KEY_NAME` - Key name in Hetzner console

**Token Scope**: `repo`, `write:packages`, `delete:packages`, `workflow`

---

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
bd dolt push          # Push beads data to remote
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
