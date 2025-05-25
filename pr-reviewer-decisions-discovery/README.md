# Pull Request Reviewer Decision Discovery

This script performs a discovery of all organization repositories and checks the last 100 Pull Request Review Decisions. It uses both REST and GraphQL API. 

The script handles rate limits and timeouts by implementing repo pagination for discovery and a delay between API calls. This makes it suitable for very large organizations.

## Prerequisites

> [!NOTE]
> IMPORTANT: [Use the best Authentication for your case](https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api)

A GitHub API token is required to run this script. 

## Usage

```bash
$ bash run.sh
Please enter the organization name:
My-Super-Cool-ORG
```

## Functionality

1. The script first checks if the GitHub API token is set. If not, it throws an error message and exits.
2. Next, it asks for the organization name.
3. It then iterates through all the pages of repositories for the given organization, storing the names of the repositories in an array.
4. It then uses a GraphQL query to retrieve the last 100 Pull Request Review Decisions for each repository. (Maybe 100 is too much? 🤔)
5. The responses from the API calls are logged in a JSON file.

## Rate Limiting

To avoid hitting rate limits, the script includes a delay of ```6 seconds``` between each API call (soooo [many factors](https://docs.github.com/en/graphql/overview/rate-limits-and-node-limits-for-the-graphql-api#predicting-the-point-value-of-a-query) to think about 🤔). Assuming an organization has 10,000 repositories, the script should take just under a day to run.

## Tests

Succesfull ran through an organization with ```1000 repositories``` and base settings in ```1.5 Hours```.

## Logs

The script creates two log files:

- A query and response log file, which logs each repository query and its response.
- A JSON response log file, which logs only the responses in JSON format.

These files are saved in the `/tmp` directory with a timestamp in their names.

## Note

If the organization does not exist or has no repositories, the script will error out.

## Disclaimer

This should be treated as a proof-of-concept. Very happy to have contributers and large organization testers report back.
