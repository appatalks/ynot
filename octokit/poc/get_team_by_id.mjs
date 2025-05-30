//
// https://docs.github.com/en/enterprise-server@3.15/rest/teams/teams?apiVersion=2022-11-28#get-a-team-by-name
// GET /orgs/{org_id}/team/{team_id}
//
import { Octokit } from "@octokit/rest";
const octokit = new Octokit({
  auth: "ghp_****", // <-- Replace with your actual token
  baseUrl: "https://git.example.com/api/v3", // <-- Update with GHES Hostname
});
const team_id = 1; // <-- Replace with Team ID
async function getTeamById() {
  try {
    const response = await octokit.request("GET /teams/{team_id}", {
      team_id,
    });
    console.log(response.data);
  } catch (error) {
    console.error("Error fetching team:", error);
  }
}
getTeamById();
