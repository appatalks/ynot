# pr-folder-search

`pr-folder-search` is a Bash script that leverages GitHub's [GraphQL API](https://docs.github.com/en/graphql) to search for pull requests that have changed files in a specific folder. 

The tool supports filtering by `author` and is ideal for pinpointing contributions that affect critical parts of your repository, like workflow configurations or other folder-specific changes.

## Features

- Query pull requests in a specific repository
- Filter results by changed files in a target folder
- Optionally filter PRs based on the author's login
- Handles pagination to retrieve all results using GitHub's GraphQL API

## Prerequisites

- Bash shell
- [curl](https://curl.se/) for HTTP requests
- [jq](https://stedolan.github.io/jq/) for JSON parsing
- A GitHub Personal Access Token (PAT) with appropriate permissions (e.g., `repo` scope)

## Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/appatalks/pr-folder-search.git
   cd pr-folder-search
   ```

2. Usage - The script expects the following usage pattern:

```bash
GITHUB_TOKEN=<your_pat> ./query_prs.sh "<OWNER>/<REPO>/<target-folder>" [author]
```

- ```OWNER``` : GitHub username or organization name.
- ```REPO``` : Repository name.
- ```target-folder``` : The folder in the repository to search for changes (e.g., .github/workflows).
- ```[author]``` : **Optional**. If provided, only pull requests authored by this user will be included.

### Examples

1. To search for pull requests in the ```appatalks/Repo-A``` repository that have changes in the ```.github/workflows``` folder:

Command:
```bash
GITHUB_TOKEN=abcdef123456 ./query_prs.sh "ExampleOrg/Repo-A/.github/workflows"
```

Response:
```bash
Searching in repository: ExampleOrg/Repo-A
Target folder: .github/workflows
---------------------------------------------
PR #114: Create accessibility.yml
URL: https://github.com/ExampleOrg/Repo-A/pull/114
Author: appatalks
Matched Files:
".github/workflows/accessibility.yml"
---------------------------------------------

---------------------------------------------
PR #113: Create 00-dependabot.yml
URL: https://github.com/ExampleOrg/Repo-A/pull/113
Author: appatalks
Matched Files:
".github/workflows/00-dependabot.yml"
---------------------------------------------

---------------------------------------------
PR #107: Bump actions/upload-artifact from 3 to 4 in /.github/workflows
URL: https://github.com/ExampleOrg/Repo-A/pull/107
Author: dependabot
Matched Files:
".github/workflows/health.yml"
".github/workflows/upload_artifact.yml"
---------------------------------------------
```

2. To search and only list PRs authored by ```appatalks```:

Command:
```bash
GITHUB_TOKEN=abcdef123456 ./query_prs.sh "ExampleOrg/Repo-A/.github/workflows" appatalks
```

Response:
```bash
Searching in repository: ExampleOrg/Repo-A
Target folder: .github/workflows
Filtering results to those authored by: appatalks
---------------------------------------------
PR #114: Create accessibility.yml
URL: https://github.com/ExampleOrg/Repo-A/pull/114
Author: appatalks
Matched Files:
".github/workflows/accessibility.yml"
---------------------------------------------

---------------------------------------------
PR #113: Create 00-dependabot.yml
URL: https://github.com/ExampleOrg/Repo-A/pull/113
Author: appatalks
Matched Files:
".github/workflows/00-dependabot.yml"
---------------------------------------------

---------------------------------------------
PR #95: Create zztop.yml
URL: https://github.com/ExampleOrg/Repo-A/pull/95
Author: appatalks
Matched Files:
".github/workflows/zztop.yml"
---------------------------------------------
```

### How It Works
1. The script constructs a GraphQL query to search for pull requests within a specific repository.
2. For each pull request, it retrieves the list of changed files.
3. It then filters those pull requests to output only those with file changes in the target folder.
4. Optionally, if an author filter is provided, it further filters for pull requests authored by the specified user.
