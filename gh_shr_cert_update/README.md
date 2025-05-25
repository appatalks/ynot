## GitHub Self-Hosted Runner Certificate Update (gh_shr_cert_update)
Getting around "[Disabling TLS certificate verification](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/monitoring-and-troubleshooting-self-hosted-runners#disabling-tls-certificate-verification)" for GitHub Self-Hosted Runners. <br>
This script adds your GitHub Enterprise Server's SSL to your Runner's certificate store.

### Usage

To use this script, download it your your Runner's Path and execute it with the following command:

```bash
curl -s https://raw.githubusercontent.com/appatalks/gh_shr_cert_update/main/add_certificate.sh -O add_certificate.sh; chmod +x add_certificate.sh; sudo bash add_certificate.sh
```

<br>

Follow the instructions. <br> When it completes it will add the needed SSL to the correct path and add additional variables to the Runner's ```.env``` file.

----

