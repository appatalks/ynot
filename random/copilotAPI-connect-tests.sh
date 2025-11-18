#!/bin/bash

# This script will leverage curl to validate the connectivity to the Copilot API
# curl -vvk https://api.githubcopilot.com/_ping -w '\n%{certs}\n'

# add results from curl below to a variable
results=$(curl -vvk https://api.githubcopilot.com/_ping -w '\n%{certs}\n' 2>/dev/null)

# check if the results contain the string "unable to check revocation"
if [[ $results == *"unable to check revocation"* ]]; then
  echo "Connectivity to certificate revocation authority cannot be establish: Firewall or Proxy issue"
else
  echo "Connectivity to Cert revocation authority successful"
fi
# Print certificate to screen
#curl -vwk https://api.githubcopilot.com/_ping -w '%{certs}' 2>/dev/null | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p'

# Create a list from URLs to test connectivity
urls=(
  "https://github.com/login"
  "https://api.github.com/user"
  "https://api.github.com/copilot_internal"
  "https://copilot-telemetry.githubusercontent.com/telemetry"
  "https://default.exp-tas.com"
  "https://copilot-proxy.githubusercontent.com/"
  "https://origin-tracker.githubusercontent.com"
  "https://api.githubcopilot.com"
)
#read list in for loop

for url in "${!urls[@]}"; do
  #echo "Testing connectivity to $url"
  # if results return not 0 then connectivity failed
  #if [[ $(curl -s ${urls[$url]} ) && $? -eq 1  ]]; then
  if [[ $(curl -L -o /dev/null -s -w "%{http_code}\n" "${urls[$url]}" 2>/dev/null) && $? -eq 0 ]]; then
    echo "Connectivity successful to: ${urls[$url]}"
  else
    echo "Connectivity error to: ${urls[$url]}"
  fi
done
