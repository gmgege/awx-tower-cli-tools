
# assign_tower_roles.sh

## Overview

`assign_tower_roles.sh` is a Bash script designed to manage role-based access for teams (`admin`, `sre`, `dev`) within **Ansible Tower (AWX)** environments that use the legacy `tower-cli`. It ensures consistent and idempotent role assignments across core resources like Projects, Inventories, Credentials, and Job Templates.

## Features

- Auto-detects existing resources (`project`, `inventory`, `credential`, `job_template`)
- Handles paginated tower-cli list responses
- Automatically creates missing teams
- Idempotent permission assignments (skips already-granted roles)
- Supports `--dry-run` for safe previewing of intended changes
- Includes `--help` for built-in documentation
- Verifies `tower-cli` is installed and authenticated

## Prerequisites

- `tower-cli` installed and configured
- `jq` installed

### Install `jq` if needed:

```bash
# RHEL/CentOS/Amazon Linux
sudo yum install jq -y

# macOS
brew install jq
```

### Configure `tower-cli` login:

```bash
tower-cli config host https://<your-tower-url>
tower-cli config username <your-username>
tower-cli config password <your-password>
```

## Usage

### Execute to assign roles (real run):

```bash
./assign_tower_roles.sh
```

### Simulate actions without making changes (dry run):

```bash
./assign_tower_roles.sh --dry-run
```

### Show help:

```bash
./assign_tower_roles.sh --help
```

## Role Assignment Logic

| Team   | Job Template | Project | Inventory | Credential |
|--------|--------------|---------|-----------|------------|
| admin  | admin        | admin   | admin     | admin      |
| sre    | admin        | use     | use       | use        |
| dev    | execute      | use     | use       | use        |

## Output Example

```bash
Detected resources:
- Project:       my-project
- Job Template:  Deploy App
- Inventory:     MyInventory
- Credential:    MyCredential

Team [admin] already exists.
Creating team [sre]...
Team [dev] already exists.

✓ [admin] already has [admin] on [inventory:MyInventory], skipped.
Granting [admin] to [sre] on [job_template:Deploy App]...
[Dry Run] Would grant [execute] to [dev] on [job_template:Deploy App]

Summary:
Total roles considered:     12
Roles already assigned:     6
Roles needing assignment:   6
```

## Notes

- This script targets Ansible Tower/AWX environments managed via `tower-cli`.
- By default, it assumes the organization name is `Default`.
- Only the first resource from each category is auto-selected for simplicity.

## License

MIT