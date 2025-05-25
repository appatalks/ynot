#!/bin/bash

SYSLOG_FILE="/var/log/syslog"
HAPROXY_LOG="/var/log/haproxy.log"

echo "Maintenance Mode Activity Report"
echo "========================================"
echo "Current Date and Time (UTC - YYYY-MM-DD HH:MM:SS formatted): $(date -u '+%Y-%m-%d %H:%M:%S')"
echo "Current User's Login: $(whoami)"
echo "========================================"
echo

# Create a temporary file to store all maintenance events
TEMP_FILE=$(mktemp)

# 1. Extract SSH CLI maintenance commands from syslog
grep 'management_console.ssh_command' "$SYSLOG_FILE" | grep 'ghe-maintenance' | while read -r line; do
    TIMESTAMP=$(echo "$line" | awk '{print $1" "$2" "$3}')
    DATE_TIME=$(echo "$line" | grep -oP '"created_at": "\K[^"]+')
    HOSTNAME=$(echo "$line" | grep -oP '"hostname": "\K[^"]+')
    USER=$(echo "$line" | grep -oP '"mc_actor": "\K[^"]+')
    ACTOR_IP=$(echo "$line" | grep -oP '"actor_ip": "\K[^"]+')
    COMMAND=$(echo "$line" | grep -oP '"command": "\K[^"]+' | sed 's/\\n//g' | tr -d '\n\r')

    if [[ "$COMMAND" == "ghe-maintenance -s" ]]; then
        ACTION="Maintenance Mode ENABLED"
        METHOD="CLI (SSH)"
    elif [[ "$COMMAND" == "ghe-maintenance -u" ]]; then
        ACTION="Maintenance Mode DISABLED"
        METHOD="CLI (SSH)"
    else
        continue
    fi

    # Add to temp file with timestamp for sorting
    UNIX_TS=$(date -d "$DATE_TIME" +%s 2>/dev/null || date -d "$TIMESTAMP" +%s 2>/dev/null || date +%s)
    echo "$TIMESTAMP|$DATE_TIME|$HOSTNAME|$USER|$ACTOR_IP|$ACTION|$METHOD|$UNIX_TS" >> "$TEMP_FILE"
done

# 2. Extract Web UI maintenance actions from haproxy.log
# For Web UI, we'll report it as TOGGLED since we can't reliably determine enable/disable
grep 'POST.*\/setup\/maintenance' "$HAPROXY_LOG" | grep -v "admin-shell" | while read -r line; do
    TIMESTAMP=$(echo "$line" | awk '{print $1" "$2" "$3}')
    
    # Extract the client IP address from the haproxy log
    CLIENT_IP=$(echo "$line" | awk '{print $6}' | cut -d':' -f1)
    
    # Extract the log date
    LOG_DATE=$(echo "$line" | grep -oP '\[\d{2}/\w+/\d{4}:\d{2}:\d{2}:\d{2}')
    if [[ -n "$LOG_DATE" ]]; then
        CLEAN_DATE=$(echo "$LOG_DATE" | tr -d '[]')
        DAY=$(echo "$CLEAN_DATE" | cut -d'/' -f1)
        MONTH=$(echo "$CLEAN_DATE" | cut -d'/' -f2)
        YEAR=$(echo "$CLEAN_DATE" | cut -d'/' -f3 | cut -d':' -f1)
        TIME=$(echo "$CLEAN_DATE" | cut -d':' -f2-4)
        
        # Convert month name to number
        case "$MONTH" in
            Jan) MONTH_NUM="01" ;;
            Feb) MONTH_NUM="02" ;;
            Mar) MONTH_NUM="03" ;;
            Apr) MONTH_NUM="04" ;;
            May) MONTH_NUM="05" ;;
            Jun) MONTH_NUM="06" ;;
            Jul) MONTH_NUM="07" ;;
            Aug) MONTH_NUM="08" ;;
            Sep) MONTH_NUM="09" ;;
            Oct) MONTH_NUM="10" ;;
            Nov) MONTH_NUM="11" ;;
            Dec) MONTH_NUM="12" ;;
        esac
        
        DATE_TIME="$YEAR-$MONTH_NUM-$DAY $TIME +0000"
        UNIX_TS=$(date -d "$DATE_TIME" +%s 2>/dev/null || date -d "$TIMESTAMP" +%s 2>/dev/null || date +%s)
    else
        DATE_TIME="Unknown Time"
        UNIX_TS=$(date -d "$TIMESTAMP" +%s 2>/dev/null || date +%s)
    fi
    
    HOSTNAME=$(echo "$line" | awk '{print $4}' | sed 's/:$//')
    USER="Admin (Web UI)"
    ACTOR_IP="$CLIENT_IP"
    ACTION="Maintenance Mode TOGGLED"
    METHOD="Web UI"

    # Add to temp file with timestamp for sorting
    echo "$TIMESTAMP|$DATE_TIME|$HOSTNAME|$USER|$ACTOR_IP|$ACTION|$METHOD|$UNIX_TS" >> "$TEMP_FILE"
done

# Sort by timestamp and display the final report
sort -t '|' -k8,8n "$TEMP_FILE" | while IFS='|' read -r TIMESTAMP DATE_TIME HOSTNAME USER ACTOR_IP ACTION METHOD UNIX_TS; do
    echo "Timestamp    : $TIMESTAMP"
    echo "Date/Time    : $DATE_TIME"
    echo "Hostname     : $HOSTNAME"
    echo "User         : $USER"
    echo "Actor IP     : $ACTOR_IP"
    echo "Action       : $ACTION"
    echo "Method       : $METHOD"
    echo "----------------------------------------"
done

# Clean up temporary file
rm -f "$TEMP_FILE"
