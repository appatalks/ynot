#### GitHub Actions Check - Secret Scanning; <br> An added layer of visibility.

> [!TIP]
> Require [status checks](https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#require-status-checks-to-pass-before-merging) to pass before merging

This GitHub Action checks for unresolved secret scanning alerts when a pull request is opened or reopened. If any unresolved alerts are found, the action will fail and report an error. 

> Q: What does this solve for, don't we already have secret scanning push protection?
> 
> A: If a secret has been previously flaged, Maintainers may ignore a secret scanning alert and _forget_ to resolve it. Others may be unaware and you **must** assume the secret is already comprimised. Why allow the risk to carry on? Let's force the issue to resolution.

#### Usage

1. **Create a Secret**
   - Add a secret named `APP_TOKEN` in your GitHub repository settings with your GitHub [token](https://github.com/appatalks/Generate_GitHub_Tokens). <br>
   - OAuth app tokens and personal access tokens (classic) need the ```repo``` scope or ```security_events``` scope to use this [endpoint](https://docs.github.com/en/enterprise-cloud@latest/rest/secret-scanning/secret-scanning?apiVersion=2022-11-28#list-secret-scanning-alerts-for-an-enterprise).

3. **Create Workflow**
   - Add the workflow [YAML file](secret-scanning-check.yml) to your repository at ```.github/workflows/secret-scanning-check.yml```.

## Notes

- Ensure your `APP_TOKEN` has the necessary permissions to access secret scanning alerts. ```security_events``` recommended.
- This action uses `jq` to process JSON data from the GitHub API.
- I love this check so much, I wanted to create a dedicated repository for it and recommend everyone use it.
