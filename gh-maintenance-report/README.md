# GH Maintenance Report

> [!NOTE]
> Proof-of-Concept - Not GitHub official

This repository provides a user-friendly report of GitHub Enterprise Server (GHES) [maintenance set and unset](https://docs.github.com/en/enterprise-server@3.16/admin/administering-your-instance/configuring-maintenance-mode/enabling-and-scheduling-maintenance-mode) periods. It parses system logs to identify maintenance mode changes and generates a readable report.

## Features

- Detects maintenance mode changes set via both CLI (SSH) and Web UI.
- Displays detailed information, including timestamps, hostname, user, actor IP, and the method used (CLI or Web UI).
- Chronologically sorts maintenance events for clarity.

## Prerequisites

- Access to `/var/log/` and relevant log file with GHES maintenance records
- Sufficient permissions to read system logs

## Usage

1. Clone the repository:

   ```bash
   git clone https://github.com/appatalks/gh-maintenance-report.git
   cd gh-maintenance-report
   ```
   
2. Make the script executable:

   ```bash
   chmod +x gh-maintenance-report.sh
   ```

3. Run the script to generate a maintenance report:

   ```bash
   sudo ./gh-maintenance-report.sh
   ```

4. Optionally, call it directly with access to `github.com`:

   ```bash
   curl -sL https://raw.githubusercontent.com/appatalks/gh-maintenance-report/main/gh-maintenance-report.sh | bash
   ```

### View the output

The script will display a detailed report of maintenance mode changes in the terminal, including:

```bash
Timestamp
Action Time
Hostname
User
Actor IP (for CLI)
Action (Enabled/Disabled)
Method (CLI or Web UI)
```

### Example

```bash
Maintenance Mode Activity Report
========================================
Current Date/Time (UTC): 2025-05-08 15:37:18
Current User's Login: admin
========================================

Timestamp    : May 8 15:09:09
Date/Time    : 2025-05-08 15:09:08 +0000
Hostname     : <Hostname>
User         : admin
Actor IP     : <IP>
Action       : Maintenance Mode ENABLED
Method       : CLI (SSH)
----------------------------------------

Timestamp    : May 8 15:25:56
Date/Time    : 2025-05-08 15:25:56.492Z
Hostname     : <Hostname>
User         : Admin (Web UI)
Actor IP     : <IP>
Action       : Maintenance Mode TOGGLED
Method       : Web UI
----------------------------------------
```
