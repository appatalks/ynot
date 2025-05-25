# List Repository Languages GitHub Action Workflow

<img src="https://github.com/appatalks/GH-Action-Repo-Language-Check/assets/4163156/80627b92-c791-47bd-8948-5443c53660bb" width="640">

This GitHub Action [Reusable Workflow](https://github.blog/2022-02-10-using-reusable-workflows-github-actions/) allows you to list the languages used in one or more repositories. It retrieves information about the languages used in each specified repository and calculates the percentage of code written in each language.

## Workflow Inputs

### `repo-urls` (required)

- Description: List of Repository URLs (comma-separated)
- Example: `https://github.com/owner1/repo1,https://github.com/owner2/repo2`
- Usage: Provide the URLs of the repositories you want to analyze.

### `use-secret-patLang` (optional)

- Description: Use [Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) for additional access
- Example: [x] Boolen sets to ```true``` to enable use of ```secrets.PATLANG```
- Usage: Create a [repository secret](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions) ```PATLANG``` with ```Personal Access Token```.

### `scan-branches` (optional)

- Description: Scan ALL branches using [Linguist](https://github.com/github-linguist/linguist) for their languages
- Example: [x] Boolen sets to ```true``` to enable use of [Linguist](https://github.com/github-linguist/linguist)

### `csv-gen` (optional with `scan-branches`)

- Description: Generate a CSV File of Branch Results
- Example: [x] Boolen sets to ```true``` to allow upload of ```output.csv``` as an [Artifact](https://docs.github.com/en/rest/actions/artifacts?apiVersion=2022-11-28)
- Usage: Download the ```output.csv``` which can be accessed in the Actions tab of your GitHub repository.

## Workflow Execution

This GitHub Action Reusable workflow consists of the following steps:

1. **Checkout Code**: The workflow checks out the code of the repository where the workflow is triggered.

2. **Extract owner and repo from URLs**: This step extracts the owner and repository name from the provided repository URLs. It then proceeds to retrieve information about the languages used in each repository.

    - For each repository URL provided, the workflow does the following:
        - Extracts the owner and repository name from the URL.
        - Uses the [GitHub API](https://docs.github.com/en/free-pro-team@latest/rest/repos/repos?apiVersion=2022-11-28#list-repository-languages) to fetch information about the languages used in the repository.
        - Calculates the percentage of code written in each language.

## Output

The results of the language analysis for each repository are displayed in the workflow's summary, which can be accessed in the Actions tab of your GitHub repository. The information includes a breakdown of languages and their respective percentages in each repository.

## How to add to your Actions

Create ```.github/workflows/check-language.yml``` file and add:

```yml
name: List Repository Languages
on:
  workflow_dispatch:
    inputs:
      repo-urls:
        description: 'List of Repository URLs (comma-separated)'
        required: true
        default: ''
        type: string
      use-secret-patLang:
        description: 'Use PAT? secrets.patLang'
        required: false
        default: false
        type: boolean
      scan-branches:
        description: 'Scan Branches'
        required: false
        default: false
        type: boolean
      csv-gen:
        description: 'Generate CSV File'
        required: false
        default: false
        type: boolean  

jobs:
  call-check-languages-workflow:
    uses: appatalks/GH-Action-Repo-Language-Check/.github/workflows/language_check.yml@main
    with:
      repo-urls: ${{ inputs.repo-urls }}
      use-secret-patLang: ${{ inputs.use-secret-patLang }}
      scan-branches: ${{ inputs.scan-branches }}
      csv-gen: ${{ inputs.csv-gen }}  
    secrets: 
      PATLANG: ${{ secrets.PATLANG }}
```

## Limitations

- Alpha Version
- Not available to GHES (Server)... just yet. Soon!

## Known Issues

- Very early release
- Needs Testing
- Needs Error Detection
