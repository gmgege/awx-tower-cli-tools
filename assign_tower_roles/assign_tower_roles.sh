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

# Detect resources
# 导出所有资源到临时文件

echo "Exporting all resources to temporary files..."
tower-cli project list -f json -a > all_projects.json
tower-cli job_template list -f json -a > all_jts.json
tower-cli inventory list -f json -a > all_inventories.json
tower-cli credential list -f json -a > all_credentials.json

echo "Loading resource names from files..."

get_resource_names() {
  local file=$1
  jq -r '.results[].name' "$file"
}

PROJECTS=( $(get_resource_names all_projects.json) )
JOB_TEMPLATES=( $(get_resource_names all_jts.json) )
INVENTORIES=( $(get_resource_names all_inventories.json) )
CREDENTIALS=( $(get_resource_names all_credentials.json) )

if [[ ${#PROJECTS[@]} -eq 0 || ${#JOB_TEMPLATES[@]} -eq 0 || ${#INVENTORIES[@]} -eq 0 || ${#CREDENTIALS[@]} -eq 0 ]]; then
  echo "Error: Required resources not found."
  exit 1
fi

echo "Detected resources:"
echo "- Projects:      ${PROJECTS[*]}"
echo "- Job Templates: ${JOB_TEMPLATES[*]}"
echo "- Inventories:   ${INVENTORIES[*]}"
echo "- Credentials:   ${CREDENTIALS[*]}"
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

# Export roles to JSON files
echo "Exporting all roles to temporary files..."
tower-cli role list -f json -a > all_roles.json

# Parse roles from JSON
get_roles() {
  local team=$1
  local resource_type=$2
  jq -r --arg team "$team" --arg type "$resource_type" '.results[] | select(.team_name == $team and .resource_type == $type) | .name' all_roles.json
}

# =====================
# Declarative Permission Matrix Configuration
# =====================
#
# To add or remove a team:
#   - Edit the TEAMS array, e.g. TEAMS=(admin sre dev qa)
#
# To add or remove a resource type:
#   - Edit the RESOURCE_TYPES array, e.g. RESOURCE_TYPES=(inventory project credential job_template)
#
# To define or change permissions:
#   - Edit the TEAM_RESOURCE_ROLES associative array.
#   - The key is in the format: <team>_<resource_type>
#   - The value is a comma-separated list of roles (e.g. "admin", "use", "execute").
#   - Example: TEAM_RESOURCE_ROLES[qa_project]=use,admin
#
# This makes it easy to maintain and extend team/resource/role assignments.

# 定义所有 team
TEAMS=(admin sre dev)

# 定义所有资源类型
RESOURCE_TYPES=(inventory project credential job_template)

# 定义权限矩阵（格式：team_resource=role1,role2,...）
declare -A TEAM_RESOURCE_ROLES
TEAM_RESOURCE_ROLES[admin_inventory]=admin
TEAM_RESOURCE_ROLES[admin_project]=admin
TEAM_RESOURCE_ROLES[admin_credential]=admin
TEAM_RESOURCE_ROLES[admin_job_template]=admin

TEAM_RESOURCE_ROLES[sre_inventory]=use
TEAM_RESOURCE_ROLES[sre_project]=use
TEAM_RESOURCE_ROLES[sre_credential]=use
TEAM_RESOURCE_ROLES[sre_job_template]=admin

TEAM_RESOURCE_ROLES[dev_inventory]=use
TEAM_RESOURCE_ROLES[dev_project]=use
TEAM_RESOURCE_ROLES[dev_credential]=use
TEAM_RESOURCE_ROLES[dev_job_template]=execute

# =====================
# 权限分配主循环
# =====================

for team in "${TEAMS[@]}"; do
  for resource_type in "${RESOURCE_TYPES[@]}"; do
    # 取资源数组变量名（如 INVENTORIES, PROJECTS ...）
    resource_var_name=$(echo "${resource_type^^}S") # 变大写加S
    resources=("${!resource_var_name}")

    # 直接从JSON获取角色列表
    roles=( $(get_roles "$team" "$resource_type") )

    for resource in "${resources[@]}"; do
      for role in "${roles[@]}"; do
        grant_role "$team" "$resource_type" "$resource" "$role"
      done
    done
  done
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