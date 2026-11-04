# Keeping Project Documentation Current

This is the completion protocol for Flashco tasks. It applies to local work, commits, push, PR/merge and build results;
it does not authorize any of those actions on its own.

## Sources of Truth

| File | Purpose | Update when |
| --- | --- | --- |
| `PRODUCT.md` | Accepted product behavior and constraints | A requirement or user-visible behavior changes |
| `history.md` | Chronological evidence of completed work | A meaningful implementation, validation, integration or build result is confirmed |
| `память.md` | Current work point, decisions, blockers and next action | The active state changes or a task completes |
| `.agents/project.md` | Technical baseline, versions, dependencies and build entry points | Versions, architecture, schema, workflows or standing verification limits change |
| `CHANGELOG.md`, `changelog.json` | Generated release history | The release procedure in `commands.md` requires it |

Do not turn the context files into three copies of the full history. Link to the authoritative detail.

## Before Work and Before Completion

1. On starting or resuming work, read the current memory and relevant project context. Verify branch, worktree,
   referenced commits and workflow state; a document's date is not proof that its statements remain true.
2. Before reporting completion, review the affected rows above. Update the relevant documents alongside the code,
   before the authorized commit. Record what changed, its code commit when known, actual checks and remaining limits.
3. A build record must include the workflow/run link, exact source commit, observed conclusion and artifact names.
   `queued`, `in_progress`, `failure`, `cancelled` and `success` are different outcomes. Record local artifact storage
   only after files are present; do not infer installation or device testing from a successful build.
4. Results obtained after the code commit belong in a follow-up documentation update under the existing authorization.
   Otherwise leave that update local and disclose the uncommitted state. Never infer permission to push or publish.
5. In memory, distinguish the latest application/build commit from later documentation commits. Record direct pushes
   to `main` as direct pushes; describe a PR as merged only after verifying its merged state.
6. Keep unresolved failures visible by name. Reuse unaffected test/review evidence, but identify its revision and do not
   claim that a later code change passed an earlier run. New edits must receive the checks that cover them.

## Documentation-Only Maintenance

- Verify statements against code, Git, actual workflow results and existing artifacts; check Markdown links and
  `git diff --check`. Do not run unrelated application tests, regenerate models or start builds for Markdown-only work.
- Keep the current documentation edit in its authorized documentation commit. Its SHA is discoverable from Git after
  commit; do not create another commit merely to write that SHA into the same documents.
- Do not append history entries for every date bump or spelling correction. A documentation-only follow-up does not
  invalidate application builds or require rebuilding the same code solely to obtain a newer document revision.
- This protocol is an agent instruction, not an installed scheduler or automatic CI freshness check. A completion
  report must identify maintained documents and disclose any relevant documentation still left behind.

Never include subscription URLs, credentials, keys, private logs or temporary build inputs. Keep machine-specific paths
in the current memory when they are needed to continue work; keep general project instructions portable.
