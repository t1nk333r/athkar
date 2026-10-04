# Issue tracker: GitHub

This repo tracks issues and specs as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: Run `gh issue view <number> --comments` to view the issue and its comments. Use `jq` to filter the comments, and fetch the labels too.
- **List issues**: Run `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`. Add appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: Run `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- **Close**: `gh issue close <number> --comment "..."`

Run `git remote -v` to identify the repo. `gh` detects it automatically inside a clone.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs follow the same labels and states as issues. Use the equivalent `gh pr` commands:

- **Read a PR**: Run `gh pr view <number> --comments` and `gh pr diff <number>` to view the diff and comments.
- **List external PRs for triage**: Run `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`, then keep only `authorAssociation` values of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE`. Drop `OWNER`, `MEMBER`, and `COLLABORATOR`.
- **Comment / label / close**: Use `gh pr comment`, `gh pr edit --add-label` or `--remove-label`, and `gh pr close`.

GitHub uses one number space for issues and PRs, so a bare `#42` could identify either. First run `gh pr view 42`. If the number is not a PR, run `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map.** Create one issue labelled `wayfinder:map` with the Notes / Decisions-so-far / Fog body. Run `gh issue create --label wayfinder:map`.
- **Child ticket.** Create a GitHub sub-issue linked to the map with `gh api` on the sub-issues endpoint. If sub-issues are not enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Apply a `wayfinder:<type>` label (`research`/`prototype`/`grilling`/`task`). Once someone claims the ticket, assign it to the driving dev.
- **Blocking.** GitHub's native issue dependencies are the canonical, UI-visible way to represent blockers. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`), not the `#number` or `node_id`. GitHub reports open blockers in `issue_dependencies_summary.blocked_by`; that field is the live gate. If dependencies are unavailable, put `Blocked by: #<n>, #<n>` at the top of the child body instead. A ticket is unblocked when every blocker is closed.
- **Frontier query.** List the map's open children with `gh issue list --state open`, scoped to the map's sub-issues or task list. Exclude children with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee. Choose the first remaining child in map order.
- **Claim.** Claim a ticket with `gh issue edit <n> --add-assignee @me`. This is the session's first write.
- **Resolve.** Comment on the ticket with `gh issue comment <n> --body "<answer>"`. Close it with `gh issue close <n>`. Then append a context pointer (gist + link) to the map's Decisions-so-far.
