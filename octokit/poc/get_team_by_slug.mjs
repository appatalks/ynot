// 
// https://docs.github.com/en/enterprise-server@3.15/rest/teams/teams?apiVersion=2022-11-28#get-a-team-by-name
// GET /orgs/{org}/teams/{team_slug}
//
import { Octokit } from "@octokit/rest";
const octokit = new Octokit({
  auth: "ghp_****", // <-- Replace with your actual token
  baseUrl: "https://git.example.com/api/v3", // <-- Update with GHES Hostname
});
const org = "org-a";        // Replace with your organization name
const team_slug = "team-a";      // Replace with your actual team slug
async function getTeamBySlug() {
  try {
    const response = await octokit.request("GET /orgs/{org}/teams/{team_slug}", {
      org,
      team_slug,
    });
    console.log(response.data);
  } catch (error) {
    console.error("Error fetching team by slug:", error);
  }
}
getTeamBySlug();
