# AWX Tower Bulk Role Assignment Automation Tool

## Project Overview
This project automates the bulk assignment of role-based permissions for teams, users, and resources (Project, Job Template, Inventory, Credential) in Ansible Tower (AWX). It supports multi-environment variable configuration, making it suitable for enterprise-level permission management.

## Directory Structure
```
assign_tower_roles_playbook.yml   # Main playbook for automated role assignment
config/
  prod.yml                       # Production environment variables
  sandbox.yml                    # Sandbox environment variables
  pipeline.yml                   # Pipeline environment variables
roles/
  ansible-modules/library/       # Custom Tower-related modules
all_projects.yaml                # Exported projects (YAML)
all_jts.yaml                     # Exported job templates (YAML)
all_credentials.yaml             # Exported credentials (YAML)
all_inventories.yaml             # Exported inventories (YAML)
all_users.yaml                   # Exported users (YAML)
```

## Variable Configuration (Multi-Environment)
- All environment variables are maintained in YAML files under the `config/` directory.
- Main variables:
  - `organization`: Organization name
  - `teams`: List of teams (admin/sre/dev)
  - `admin_user`: List of usernames to be added to the admin team
  - `sre_user`: List of usernames to be added to the sre team
  - All other users will be added to the dev team automatically
- **To select an environment, specify the variable file when running the playbook:**
  ```sh
  ansible-playbook assign_tower_roles_playbook.yml --extra-vars '@config/prod.yml'
  # or for sandbox:
  ansible-playbook assign_tower_roles_playbook.yml --extra-vars '@config/sandbox.yml'
  # or for pipeline:
  ansible-playbook assign_tower_roles_playbook.yml --extra-vars '@config/pipeline.yml'
  ```

## How to Run
1. **Prepare dependencies**
   - Install `ansible` (recommended 2.8.4)
   - Install and configure `tower-cli` with access to your Tower/AWX instance
   - Ensure `roles/ansible-modules/library` is set in the `library` path in your `ansible.cfg`
2. **Change to the project directory**
3. **Run the playbook with the desired environment**
   ```sh
   ansible-playbook assign_tower_roles_playbook.yml --extra-vars '@config/prod.yml'
   ```
   For a dry-run, add `--check`

## Main Logic
1. **Load environment variables**: Loads variables from the specified YAML file via `--extra-vars`
2. **Organization/Team creation**: Ensures the specified organization and teams exist
3. **Resource export**: Uses `tower-cli` to export all Projects, Job Templates, Credentials, Inventories, and Users to **YAML files** (not JSON)
4. **YAML parsing**: The playbook uses Ansible's `from_yaml` filter to parse these files
5. **User grouping**:
   - Users in `admin_user` are added to the admin team
   - Users in `sre_user` are added to the sre team
   - All other users are added to the dev team
6. **Bulk role assignment**:
   - The admin team is granted admin rights on all resources
   - The sre team is granted admin on job_templates and use on other resources
   - The dev team is granted execute on job_templates and use on other resources

## Dependencies
- ansible >=2.8.4
- tower-cli (with valid authentication/configuration)
- jq (for JSON output parsing by tower-cli, not needed for YAML)
- AWX/Tower API permissions

## FAQ
- If custom modules are not found, check the `library` path in your `ansible.cfg`
- Usernames must match those in Tower
- Playbook execution time may increase with a large number of resources

---
For questions, please contact the maintainer. 