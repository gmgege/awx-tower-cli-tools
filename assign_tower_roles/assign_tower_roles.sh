#!/bin/bash

# Usage function for --help
print_help() {
  cat <<EOF
Usage: ./assign_tower_roles.sh [--dry-run] [--help]

This script assigns role-based permissions to three teams (admin, sre, dev)
for existing resources in an Ansible Tower environment using tower-cli.

Optional arguments:
  --dry-run       Simulate actions without applying any changes.
  --help, -h      Show this help message and exit.

Example:
  ./assign_tower_roles.sh
  ./assign_tower_roles.sh --dry-run
EOF
}

# Parse arguments
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help|-h) print_help; exit 0 ;;
    *) echo "Unknown argument: $arg"; print_help; exit 1 ;;
  esac
done

if $DRY_RUN; then
  echo "[Dry Run] No actual changes will be made."
fi

# Verify tower-cli is installed and configured
check_tower_cli_auth() {
  if ! command -v tower-cli >/dev/null 2>&1; then
    echo "Error: tower-cli is not installed."
    exit 1
  fi

  if ! tower-cli user list -f json >/dev/null 2>&1; then
    echo "Error: tower-cli is not authenticated or misconfigured."
    echo "Please configure it with:"
    echo "  tower-cli config host <url>"
    echo "  tower-cli config username <user>"
    echo "  tower-cli config password <password>"
    exit 1
  fi
}

check_tower_cli_auth

# Function to get first resource name with pagination
get_first_resource_name() {
  local type=$1
  local page=1
  while true; do
    data=$(tower-cli $type list --page $page -f json)
    if [[ $(echo "$data" | jq length) -eq 0 ]]; then
      break
    fi
    name=$(echo "$data" | jq -r '.[0].name')
    if [[ -n "$name" ]]; then
      echo "$name"
      return
    fi
    page=$((page + 1))
  done
  echo ""
}

# Detect resources
PROJECT=$(get_first_resource_name project)
JOB_TEMPLATE=$(get_first_resource_name job_template)
INVENTORY=$(get_first_resource_name inventory)
CREDENTIAL=$(get_first_resource_name credential)

if [[ -z "$PROJECT" || -z "$JOB_TEMPLATE" || -z "$INVENTORY" || -z "$CREDENTIAL" ]]; then
  echo "Error: Required resources not found."
  exit 1
fi

echo "Detected resources:"
echo "- Project:       $PROJECT"
echo "- Job Template:  $JOB_TEMPLATE"
echo "- Inventory:     $INVENTORY"
echo "- Credential:    $CREDENTIAL"
echo ""

# Auto-create teams if missing
ensure_team_exists() {
  local team_name=$1
  local org_name="Default"
  if tower-cli team list --organization "$org_name" -f json | jq -e ".[] | select(.name == \"$team_name\")" >/dev/null; then
    echo "Team [$team_name] already exists."
  else
    echo "Creating team [$team_name]..."
    tower-cli team create --name "$team_name" --organization "$org_name"
  fi
}

for team in admin sre dev; do
  ensure_team_exists "$team"
done

# Check if role already assigned
role_exists() {
  local team=$1
  local resource=$2
  local name=$3
  local role=$4
  local page=1
  while true; do
    data=$(tower-cli role list --type "$resource" --name "$name" --team "$team" --page $page -f json)
    if [[ $(echo "$data" | jq length) -eq 0 ]]; then
      break
    fi
    if echo "$data" | jq -e ".[] | select(.name == \"$role\")" >/dev/null; then
      return 0
    fi
    page=$((page + 1))
  done
  return 1
}

# Grant role if not already granted
grant_role() {
  local team=$1 resource=$2 name=$3 role=$4
  ((total++))
  if role_exists "$team" "$resource" "$name" "$role"; then
    ((already_assigned++))
    echo "✓ [$team] already has [$role] on [$resource:$name], skipped."
  else
    ((to_assign++))
    if $DRY_RUN; then
      echo "[Dry Run] Would grant [$role] to [$team] on [$resource:$name]"
    else
      echo "Granting [$role] to [$team] on [$resource:$name]..."
      tower-cli role grant --type "$resource" --name "$name" --team "$team" --role "$role"
    fi
  fi
}

# Assign roles
total=0
already_assigned=0
to_assign=0

for team in admin sre dev; do
  if [[ "$team" == "admin" ]]; then
    grant_role "$team" inventory "$INVENTORY" admin
    grant_role "$team" project "$PROJECT" admin
    grant_role "$team" credential "$CREDENTIAL" admin
    grant_role "$team" job_template "$JOB_TEMPLATE" admin
  elif [[ "$team" == "sre" ]]; then
    grant_role "$team" job_template "$JOB_TEMPLATE" admin
    grant_role "$team" inventory "$INVENTORY" use
    grant_role "$team" project "$PROJECT" use
    grant_role "$team" credential "$CREDENTIAL" use
  elif [[ "$team" == "dev" ]]; then
    grant_role "$team" job_template "$JOB_TEMPLATE" execute
    grant_role "$team" inventory "$INVENTORY" use
    grant_role "$team" project "$PROJECT" use
    grant_role "$team" credential "$CREDENTIAL" use
  fi
done

echo ""
echo "Summary:"
echo "Total roles considered:     $total"
echo "Roles already assigned:     $already_assigned"
echo "Roles needing assignment:   $to_assign"

if $DRY_RUN; then
  echo "No changes were made (dry-run mode)."
else
  echo "Role assignment complete."
fi