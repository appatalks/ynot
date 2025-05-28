#!/bin/bash

# GitHub Actions Workflow Analysis Script
# For analyzing workflow data in GitHub Enterprise Server audit logs
# Usage: ./analyze_workflows.sh [path_to_logs]

set -e

# Default log location
LOG_PATH="./github-logs/github-audit.log"

# If the default log file doesn't exist, try the alternative path
if [[ ! -f "$LOG_PATH" && -f "/var/log/github-audit.log" ]]; then
  LOG_PATH="/var/log/github-audit.log"
fi

# Create a temporary directory for working files
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "===================================================================="
echo "GitHub Actions Workflow Analysis"
echo "Analyzing logs from: $LOG_PATH"
echo "===================================================================="

# Check if logs exist and are accessible
if ! ls $LOG_PATH &>/dev/null; then
  echo "Error: No log files found at $LOG_PATH"
  exit 1
fi

echo -e "\n[1/5] Extracting workflow events..."

# Extract workflow creation events - use only the most recent log file to avoid excessive processing
grep "workflows.created_workflow_run" $LOG_PATH > "$TEMP_DIR/created_workflows.txt" || {
  echo "No workflow creation events found!"
  CREATED_COUNT=0
}

# Extract workflow completion events
grep "workflows.completed_workflow_run" $LOG_PATH > "$TEMP_DIR/completed_workflows.txt" || {
  echo "No workflow completion events found!"
  COMPLETED_COUNT=0
}

CREATED_COUNT=$(wc -l < "$TEMP_DIR/created_workflows.txt" 2>/dev/null || echo "0")
COMPLETED_COUNT=$(wc -l < "$TEMP_DIR/completed_workflows.txt" 2>/dev/null || echo "0")

echo "Found $CREATED_COUNT workflow creation events"
echo "Found $COMPLETED_COUNT workflow completion events"

# Extract timestamps and determine log time range
if [ "$CREATED_COUNT" -gt 0 ]; then
  echo -e "\n[2/5] Determining log time range and analyzing workflow activity..."
  
  # Extract the created_at timestamps
  grep -o '"created_at":[0-9]*' "$TEMP_DIR/created_workflows.txt" | cut -d':' -f2 > "$TEMP_DIR/timestamps.txt"
  
  # Find the newest and oldest timestamps in milliseconds
  if [ -s "$TEMP_DIR/timestamps.txt" ]; then
    NEWEST_TS=$(sort -nr "$TEMP_DIR/timestamps.txt" | head -1)
    OLDEST_TS=$(sort -n "$TEMP_DIR/timestamps.txt" | head -1)
    
    # Convert to seconds if needed
    if [ ${#NEWEST_TS} -gt 10 ]; then
      NEWEST_TS_SEC=$((NEWEST_TS/1000))
      OLDEST_TS_SEC=$((OLDEST_TS/1000))
    else
      NEWEST_TS_SEC=$NEWEST_TS
      OLDEST_TS_SEC=$OLDEST_TS
    fi
    
    # Format timestamps for display
    NEWEST_DATE=$(date -d @$NEWEST_TS_SEC "+%Y-%m-%d %H:%M:%S")
    OLDEST_DATE=$(date -d @$OLDEST_TS_SEC "+%Y-%m-%d %H:%M:%S")
    
    # Calculate log duration
    LOG_DURATION_SEC=$((NEWEST_TS_SEC - OLDEST_TS_SEC))
    LOG_DURATION_HOURS=$((LOG_DURATION_SEC / 3600))
    LOG_DURATION_DAYS=$((LOG_DURATION_SEC / 86400))
    
    echo "Log covers period from $OLDEST_DATE to $NEWEST_DATE"
    echo "Total log duration: $LOG_DURATION_DAYS days, $((LOG_DURATION_HOURS % 24)) hours ($LOG_DURATION_SEC seconds)"
    
    # Create time analysis script using the newest timestamp as reference point
    cat > "$TEMP_DIR/analyze_time.sh" << EOF
#!/bin/bash

newest_ts=$NEWEST_TS_SEC
count_1h=0
count_2h=0
count_4h=0
count_8h=0
count_24h=0
total=0

while read timestamp; do
  # Convert milliseconds to seconds if needed
  if [ \${#timestamp} -gt 10 ]; then
    timestamp=\$((timestamp/1000))
  fi
  
  time_diff=\$((newest_ts - timestamp))
  
  if [ \$time_diff -le 3600 ]; then
    ((count_1h++))
  fi
  if [ \$time_diff -le 7200 ]; then
    ((count_2h++))
  fi
  if [ \$time_diff -le 14400 ]; then
    ((count_4h++))
  fi
  if [ \$time_diff -le 28800 ]; then
    ((count_8h++))
  fi
  if [ \$time_diff -le 86400 ]; then
    ((count_24h++))
  fi
  ((total++))
done < "\$1"

echo "Last 1 hour of logs: \$count_1h workflow runs"
echo "Last 2 hours of logs: \$count_2h workflow runs"
echo "Last 4 hours of logs: \$count_4h workflow runs"
echo "Last 8 hours of logs: \$count_8h workflow runs"
echo "Last 24 hours of logs: \$count_24h workflow runs"
echo "Total workflows in log: \$total"
EOF
    chmod +x "$TEMP_DIR/analyze_time.sh"
    
    # Analyze timestamps
    "$TEMP_DIR/analyze_time.sh" "$TEMP_DIR/timestamps.txt"
    
    # Calculate average runs per hour and per day
    if [ $LOG_DURATION_SEC -gt 0 ]; then
      RUNS_PER_HOUR=$(awk "BEGIN {printf \"%.2f\", $CREATED_COUNT / ($LOG_DURATION_SEC / 3600)}")
      RUNS_PER_DAY=$(awk "BEGIN {printf \"%.2f\", $CREATED_COUNT / ($LOG_DURATION_SEC / 86400)}")
      
      echo -e "\nAverage workflow activity:"
      echo "  $RUNS_PER_HOUR workflows per hour"
      echo "  $RUNS_PER_DAY workflows per day"
    fi
  else
    echo "Could not determine timestamp range from logs."
  fi
else
  echo -e "\n[2/5] Skipping time-based analysis (no creation events found)"
fi

# Analyze workflow durations
if [ "$CREATED_COUNT" -gt 0 ] && [ "$COMPLETED_COUNT" -gt 0 ]; then
  echo -e "\n[3/5] Finding longest running workflows..."
  
  # Create workflow duration analyzer - reference against log time range
  cat > "$TEMP_DIR/find_durations.sh" << 'EOF'
#!/bin/bash

declare -A start_times
declare -A repos
declare -A names
declare -A durations
declare -A workflows
declare -A branches

# Process each creation event
while read -r line; do
  # Extract workflow run ID
  workflow_id=$(echo "$line" | grep -o '"workflow_run_id":[0-9]*' | cut -d':' -f2)
  if [ -z "$workflow_id" ]; then
    workflow_id=$(echo "$line" | grep -o '"workflow_run_id":"[^"]*"' | cut -d'"' -f4)
  fi
  
  # Skip if no workflow ID found
  if [ -z "$workflow_id" ]; then
    continue
  fi
  
  # Extract timestamp
  timestamp=$(echo "$line" | grep -o '"created_at":[0-9]*' | cut -d':' -f2)
  
  # Extract repo name
  repo=$(echo "$line" | grep -o '"repo":"[^"]*"' | cut -d'"' -f4)
  
  # Extract workflow name
  name=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
  
  # Extract branch name (if available)
  branch=$(echo "$line" | grep -o '"head_branch":"[^"]*"' | cut -d'"' -f4)
  
  # Store data for creation events
  if [[ $line == *"workflows.created_workflow_run"* ]]; then
    start_times[$workflow_id]=$timestamp
    repos[$workflow_id]=$repo
    names[$workflow_id]=$name
    branches[$workflow_id]=$branch
    workflows[$workflow_id]=1
  fi
done < "$1"

# Process each completion event
while read -r line; do
  # Extract workflow run ID
  workflow_id=$(echo "$line" | grep -o '"workflow_run_id":[0-9]*' | cut -d':' -f2)
  if [ -z "$workflow_id" ]; then
    workflow_id=$(echo "$line" | grep -o '"workflow_run_id":"[^"]*"' | cut -d'"' -f4)
  fi
  
  # Skip if no workflow ID found or no start time exists
  if [ -z "$workflow_id" ] || [ -z "${start_times[$workflow_id]}" ]; then
    continue
  fi
  
  # Extract timestamp
  timestamp=$(echo "$line" | grep -o '"created_at":[0-9]*' | cut -d':' -f2)
  
  # Extract conclusion (if available)
  conclusion=$(echo "$line" | grep -o '"conclusion":"[^"]*"' | cut -d'"' -f4)
  
  # Calculate duration in seconds
  start=${start_times[$workflow_id]}
  
  # Both are in milliseconds - convert to seconds
  if [ ${#timestamp} -gt 10 ] && [ ${#start} -gt 10 ]; then
    duration=$(( (timestamp - start) / 1000 ))
  else
    duration=$((timestamp - start))
  fi
  
  if [ $duration -gt 0 ]; then
    durations[$workflow_id]=$duration
  fi
done < "$2"

# Print results
echo "Workflow_ID,Repository,Workflow_Name,Branch,Duration_Seconds,Duration_Minutes,Duration_Hours"

for id in "${!durations[@]}"; do
  duration=${durations[$id]}
  minutes=$(echo "scale=2; $duration / 60" | bc)
  hours=$(echo "scale=2; $minutes / 60" | bc)
  branch="${branches[$id]:-unknown}"
  echo "$id,${repos[$id]},${names[$id]},$branch,$duration,$minutes,$hours"
done | sort -t',' -k5,5nr | head -20
EOF
  chmod +x "$TEMP_DIR/find_durations.sh"
  
  # Run duration analysis
  cd "$TEMP_DIR"
  ./find_durations.sh "created_workflows.txt" "completed_workflows.txt" > "longest_workflows.csv"
  
  # Display results in a formatted table
  if [ -s "longest_workflows.csv" ]; then
    echo "Top 20 longest running workflows:"
    column -t -s',' "longest_workflows.csv" | sed 's/^/  /'
    
    # Calculate overall stats
    if command -v bc &>/dev/null; then
      total_workflows=$(grep -v "Workflow_ID" longest_workflows.csv | wc -l)
      if [ "$total_workflows" -gt 0 ]; then
        total_seconds=$(grep -v "Workflow_ID" longest_workflows.csv | awk -F',' '{sum+=$5} END {print sum}')
        avg_seconds=$(echo "scale=2; $total_seconds / $total_workflows" | bc)
        avg_minutes=$(echo "scale=2; $avg_seconds / 60" | bc)
        max_seconds=$(grep -v "Workflow_ID" longest_workflows.csv | awk -F',' '{print $5}' | sort -nr | head -1)
        max_minutes=$(echo "scale=2; $max_seconds / 60" | bc)
        max_hours=$(echo "scale=2; $max_seconds / 3600" | bc)
        
        echo -e "\nWorkflow Duration Statistics:"
        echo "  Average duration: $avg_seconds seconds ($avg_minutes minutes)"
        echo "  Longest duration: $max_seconds seconds ($max_minutes minutes, $max_hours hours)"
      fi
    fi
  else
    echo "No workflow duration data could be calculated"
  fi
  cd - > /dev/null
else
  echo -e "\n[3/5] Skipping workflow duration analysis (insufficient events)"
fi

# Analyze workflow triggers
echo -e "\n[4/5] Analyzing workflow trigger events..."

if [ "$CREATED_COUNT" -gt 0 ]; then
  # Extract workflow trigger events
  grep -o '"event":"[^"]*"' "$TEMP_DIR/created_workflows.txt" | cut -d'"' -f4 | sort | uniq -c | sort -nr > "$TEMP_DIR/trigger_events.txt" || {
    echo "Could not extract trigger events"
  }
  
  if [ -s "$TEMP_DIR/trigger_events.txt" ]; then
    echo "Top workflow triggers:"
    awk '{printf "  %-20s %s\n", $2, $1}' "$TEMP_DIR/trigger_events.txt" | head -10
  else
    echo "No trigger event data found"
  fi
  
  # Top repositories using Actions
  grep -o '"repo":"[^"]*"' "$TEMP_DIR/created_workflows.txt" | cut -d'"' -f4 | sort | uniq -c | sort -nr > "$TEMP_DIR/top_repos.txt" || {
    echo "Could not extract repository data"
  }
  
  if [ -s "$TEMP_DIR/top_repos.txt" ]; then
    echo -e "\nTop repositories using GitHub Actions:"
    awk '{printf "  %-50s %s\n", $2, $1}' "$TEMP_DIR/top_repos.txt" | head -10
  fi
else
  echo "No workflow creation events found for trigger analysis"
fi

# Analyze workflow completions for monthly usage
echo -e "\n[5/5] Calculating usage statistics..."

if [ "$COMPLETED_COUNT" -gt 0 ]; then
  # Try to extract workflow durations
  grep "workflows.completed_workflow_run" $LOG_PATH | grep -o '"workflow_run_duration":[0-9]*' | cut -d':' -f2 > "$TEMP_DIR/durations.txt" || {
    echo "Could not extract workflow run durations - trying workflow_job_duration instead"
    grep "workflows.completed_workflow_run" $LOG_PATH | grep -o '"workflow_job_duration":[0-9]*' | cut -d':' -f2 > "$TEMP_DIR/durations.txt" || {
      echo "Could not extract workflow job durations either"
    }
  }
  
  if [ -s "$TEMP_DIR/durations.txt" ]; then
    # Create script to analyze usage
    cat > "$TEMP_DIR/usage_stats.sh" << 'EOF'
#!/bin/bash

total_milliseconds=0
total_workflows=0
max_duration=0

while read -r duration; do
  # Add to total
  total_milliseconds=$((total_milliseconds + duration))
  
  # Track max duration
  if [ $duration -gt $max_duration ]; then
    max_duration=$duration
  fi
  
  ((total_workflows++))
done < "$1"

# Convert to minutes
total_minutes=$(echo "scale=2; $total_milliseconds / 60000" | bc)
avg_minutes=$(echo "scale=2; $total_minutes / $total_workflows" | bc)
max_minutes=$(echo "scale=2; $max_duration / 60000" | bc)

echo "Total workflow runs analyzed: $total_workflows"
echo "Total minutes consumed: $total_minutes"
echo "Average workflow duration: $avg_minutes minutes"
echo "Longest workflow duration: $max_minutes minutes"

# Calculate daily and monthly estimates based on the log timeframe
if [ $2 -gt 0 ] && [ $3 -gt 0 ]; then
  # Log duration in days
  log_days=$(echo "scale=4; $2 / 86400" | bc)
  
  # Calculate daily and monthly estimates
  daily_runs=$(echo "scale=2; $3 / $log_days" | bc)
  daily_minutes=$(echo "scale=2; $daily_runs * $avg_minutes" | bc)
  monthly_runs=$(echo "scale=0; $daily_runs * 30" | bc)
  monthly_minutes=$(echo "scale=0; $daily_minutes * 30" | bc)
  
  echo -e "\nEstimated usage (based on log data):"
  echo "  Estimated workflows per day: $daily_runs"
  echo "  Estimated minutes per day: $daily_minutes"
  echo "  Estimated workflows per month: $monthly_runs"
  echo "  Estimated minutes per month: $monthly_minutes"
fi
EOF
    chmod +x "$TEMP_DIR/usage_stats.sh"
    
    # Run usage stats analysis
    "$TEMP_DIR/usage_stats.sh" "$TEMP_DIR/durations.txt" "$LOG_DURATION_SEC" "$CREATED_COUNT"
  else
    echo "No workflow duration data found"
  fi
  
  # Check workflow success/failure statistics
  grep "workflows.completed_workflow_run" $LOG_PATH | grep -o '"conclusion":"[^"]*"' | cut -d'"' -f4 | sort | uniq -c | sort -nr > "$TEMP_DIR/conclusions.txt" || {
    echo "Could not extract workflow conclusions"
  }
  
  if [ -s "$TEMP_DIR/conclusions.txt" ]; then
    TOTAL_CONCLUSIONS=$(awk '{sum+=$1} END {print sum}' "$TEMP_DIR/conclusions.txt")
    
    if [ ! -z "$TOTAL_CONCLUSIONS" ] && [ "$TOTAL_CONCLUSIONS" -gt 0 ]; then
      echo -e "\nWorkflow conclusion statistics:"
      while read COUNT CONCLUSION; do
        PERCENTAGE=$(echo "scale=2; ($COUNT * 100) / $TOTAL_CONCLUSIONS" | bc)
        printf "  %-15s %8d (%6.2f%%)\n" "$CONCLUSION:" "$COUNT" "$PERCENTAGE"
      done < "$TEMP_DIR/conclusions.txt"
    fi
  fi
else
  echo "No workflow completion events found for usage statistics"
fi

echo -e "\n===================================================================="
echo "Analysis complete."
echo "===================================================================="

# Clean up temporary files
exit 0
