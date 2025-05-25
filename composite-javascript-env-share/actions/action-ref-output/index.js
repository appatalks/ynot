const core = require('@actions/core');
const github = require('@actions/github');

try {
  // The GitHub context contains all the information about the event that triggered the workflow
  const context = github.context;
  
  // Extract the action_ref from the context
  // This could be a branch name (refs/heads/main), tag (refs/tags/v1), or SHA
  const actionRef = process.env.GITHUB_REF || '';
  
  console.log(`Action ref from index.js: ${actionRef}`);
  
  // Set the output so it can be used in subsequent steps
  core.setOutput('action_ref', actionRef);
  
} catch (error) {
  console.error(`Action failed with error: ${error.message}`);
  process.exit(1);
}
