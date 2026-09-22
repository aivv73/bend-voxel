# Issue tracker: GitHub

Issues and specifications live in [GitHub Issues for aivv73/bend-voxel](https://github.com/aivv73/bend-voxel/issues). Use the `gh` CLI from this repository. Write titles, descriptions, and documentation in English.

## Conventions

- **Create:** `gh issue create --title "..." --body-file <file>`.
- **Read:** `gh issue view <number> --comments`.
- **Read structured data:** `gh issue view <number> --json number,title,body,labels,comments`.
- **List:** `gh issue list --state open --json number,title,body,labels,comments`, with appropriate label and state filters.
- **Comment:** `gh issue comment <number> --body-file <file>`.
- **Apply or remove labels:** `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- **Close:** `gh issue close <number>`.

For multiline text, write the exact content to a file with real newlines and use `--body-file`. Infer the repository from `git remote -v`; `gh` does this automatically inside the clone.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Skill terminology

“Publish to the issue tracker” means create a GitHub issue. “Fetch the relevant ticket” means read its description, labels, and comments.

## Wayfinding operations

- **Map:** a single issue labeled `wayfinder:map`, containing Notes, Decisions-so-far, and Fog.
- **Child ticket:** link the issue to the map as a GitHub sub-issue. If sub-issues are unavailable, add the child to a task list in the map and place `Part of #<map>` at the top of the child body. Use `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task` for the type.
- **Blocking:** use GitHub's native issue dependencies. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`. Obtain the numeric database ID with `gh api repos/<owner>/<repo>/issues/<number> --jq .id`; it is not the issue number or node ID. If dependencies are unavailable, use a `Blocked by: #<number>` line in the child body. A ticket is unblocked when all blockers are closed.
- **Frontier:** list the map's open children, exclude assigned tickets and those with open blockers, and select the first remaining ticket in map order. Check `issue_dependencies_summary.blocked_by` or the fallback references.
- **Claim:** assign the ticket to the driving developer before working on it; use `gh issue edit <number> --add-assignee @me` for the current user.
- **Resolve:** comment with the result, close the ticket, and add a summary and link to the map's Decisions-so-far section.
