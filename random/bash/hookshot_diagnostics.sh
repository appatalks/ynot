#!/bin/bash
#
hookshot_logs='/var/log/syslog'
echo
echo "Top 10 successful webhook destinations we contacted:"
rg -N '(Body|msg)="Delivery ' "$hookshot_logs" | rg -N 'status=2' | grep -oP '(http|https)?:\/\/(\S+)' | sort | uniq -c | sort -rn | head
echo
echo "Top 10 dest with most seen error messages:"
grep -F "hookshot-go[" "$hookshot_logs" | grep -o 'public_error_message="[^"]*"' | awk -F '"' '{ print $2 }' | sort | uniq -c | sort -rn | head
echo
echo "Top 10 dest with timeouts:"
rg -N 'public_error_message="timed out"' "$hookshot_logs" | grep -o "dest_url=[^ ]*" | awk -F '=' '{ print $2 }' | sort | uniq -c | sort -rn | head
echo
echo "Top 10 dest with connection issues:"
rg -N 'public_error_message="[^"]*connection refused"' "$hookshot_logs" | grep -o "dest_url=[^ ]*" | awk -F '=' '{ print $2 }' | sort | uniq -c | sort -rn | head
echo
echo "Top 10 dest with connections reset by peer:"
rg -N 'public_error_message="[^"]*connection reset by peer"' "$hookshot_logs" | grep -o "dest_url=[^ ]*" | awk -F '=' '{ print $2 }' | sort | uniq -c | sort -rn | head
echo
echo "Top 10 dest with Service Unavailable:"
rg -N 'public_error_message="Service Unavailable"' "$hookshot_logs" | grep -o "dest_url=[^ ]*" | awk -F '=' '{ print $2 }' | sort | uniq -c | sort -rn | head
echo
echo "Top 10 dest with DNS resolution issues:"
rg -N 'public_error_message="[^"]*no such host"' "$hookshot_logs" | grep -o "dest_url=[^ ]*" | awk -F '=' '{ print $2 }' | sort | uniq -c | sort -rn | head
echo
echo "Top 10 dest with SSL issues:"
rg -N 'public_error_message="[^"]*certificate' "$hookshot_logs" | grep -o "dest_url=[^ ]*" | awk -F '=' '{ print $2 }' | sort | uniq -c | sort -rn | head
