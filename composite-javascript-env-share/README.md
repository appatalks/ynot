# GitHub Action Ref Output

This is a simple `proof-of-concept` GitHub Action for passing environment variables from a composite action to a JavaScript action, where in this example the outputs for `github.action_ref` value.

## Purpose

The purpose of this action is to demonstrate how to create a GitHub Action that:
1. Retrieves and outputs the reference (`branch`, `tag`, or `commit SHA`) that triggered the action.
2. Checks whether the action is being called via a pinned reference (`tag` or `commit SHA`) and warns if it is not.

## Example Output

- If the action is properly pinned:
  ```
  ✅ All clear! This action is properly pinned to a tag or commit SHA.
  ```

- If the action is not properly pinned:
  ```
  ⚠️ WARNING: This action is referenced via the "main" branch.
  For security reasons, it is recommended to pin actions to a specific version tag or commit SHA.
  Example: uses: username/repo@v1.0.0
  ```

## License

This project is licensed under the MIT License.
