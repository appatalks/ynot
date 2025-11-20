#!/bin/bash

OUTFILE="diagnostic_$(date '+%Y%m%d_%H%M').log"

log_and_run() {
    echo "========================================================" >> "$OUTFILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$OUTFILE"
    echo "--------------------------------------------------------" >> "$OUTFILE"
    # Run command, tee output and errors
    { time "$@"; } 2>&1 | tee -a "$OUTFILE"
    echo >> "$OUTFILE"
}

echo "Starting diagnostics at $(date)" > "$OUTFILE"
echo "" >> "$OUTFILE"

log_and_run dig api.github.com
log_and_run ping -c 30 api.github.com
log_and_run ping -c 30 -M do -s 1472 api.github.com
log_and_run openssl s_client -connect api.github.com:443 -servername api.github.com

echo ""
echo "Please standby..."

echo "========================================================" >> "$OUTFILE"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Looping openssl s_client 30 times" >> "$OUTFILE"
echo "--------------------------------------------------------" >> "$OUTFILE"

for i in {1..30}; do
    echo "Try $i:" >> "$OUTFILE"
    timeout 5 openssl s_client -connect api.github.com:443 -servername api.github.com < /dev/null 2>&1 | egrep 'CONNECTED|verify|ssl|Certificate|Cipher|Protocol' >> "$OUTFILE"
    echo "----" >> "$OUTFILE"
    sleep 1
done

echo ""
echo "Please standby..."

log_and_run mtr -c 30 -r api.github.com
log_and_run netstat -i
log_and_run netstat -s
log_and_run chronyc tracking
log_and_run sudo hwclock --show

echo ""
echo "Diagnostics finished at $(date)" >> "$OUTFILE"
echo "Diagnostics Completed!"
echo "Run to provide diagnostics to Support: " 
echo ""
echo "ghe-support-upload -t <<TICKET-ID>> -d $HOSTNAME $OUTFILE"
