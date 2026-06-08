# Worktree Command Implementations

Detailed process steps for each `/cw-worktree` command. Referenced from [SKILL.md](../SKILL.md).

---

## create

**Per-invocation setup (runs once, before the per-feature loop):**

Resolve the `cw-herdr-open` helper and probe herdr availability **once** for the whole multi-create call. The result is reused for every feature — there is no point probing the same daemon `N` times when the answer cannot change between worktrees on a single host.

**Helper resolution** uses three lookups in priority order: PATH (the plugin's `bin/` is auto-added to Claude's session PATH at startup, so `command -v` works for marketplace installs), `CLAUDE_PLUGIN_ROOT` (set in hooks but not in Bash by default), and the git top-level (useful only when running from a plugin source checkout).

```bash
# Primary: marketplace installs put plugin bin/ on Claude's PATH
HERDR_OPEN_BIN="$(command -v cw-herdr-open 2>/dev/null || true)"
# Fallback 1: explicit plugin root (set in hook context)
if [ -z "$HERDR_OPEN_BIN" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  HERDR_OPEN_BIN="$CLAUDE_PLUGIN_ROOT/bin/cw-herdr-open"
fi
# Fallback 2: plugin source checkout only — for any other repo this resolves
# to a non-existent path and the [ -x ] guard below trips, falling through
# to the legacy output.
if [ -z "$HERDR_OPEN_BIN" ] || [ ! -x "$HERDR_OPEN_BIN" ]; then
  HERDR_OPEN_BIN="$(git rev-parse --show-toplevel 2>/dev/null)/bin/cw-herdr-open"
fi

# Probe once for the whole multi-create call.
HERDR_AVAILABLE=0
HERDR_PROBE_EXIT=2
if [ -x "$HERDR_OPEN_BIN" ]; then
  "$HERDR_OPEN_BIN" --probe 2>/dev/null
  HERDR_PROBE_EXIT=$?
  [ "$HERDR_PROBE_EXIT" -eq 0 ] && HERDR_AVAILABLE=1
fi
```

`HERDR_PROBE_EXIT` carries the original 0/2/3 exit code. Step 9 reuses it as `HERDR_EXIT` when herdr is unavailable, so step 10 can distinguish exit 3 (daemon down — say so in the fallback summary) from exit 2 (not installed or `CW_DISABLE_HERDR=1` — stay silent). For diagnosis run `cw-herdr-open --probe; echo $?` directly — see SKILL.md "Diagnosing the herdr integration".

**Drive-mode selection (runs once for the whole batch):**

After classifying each feature into a `STARTER_PROMPT` / `STARTER_PROMPT_GOAL` (see SKILL.md "Starter Prompt Generation"), but **before** entering the per-feature loop, present a single `AskUserQuestion` to pick `DRIVE_MODE ∈ {starter, autonomous, empty, skip_herdr}`. The full question shape, option-collapsing rules, and label-to-mode mapping live in SKILL.md "Drive-Mode Selection". The chosen `DRIVE_MODE` is cached and read by step 9 of every feature in this call — there is no per-worktree confirmation.

Fire the question even under a standing "work without clarifying questions" instruction. Skip it only when zero meaningful options remain (no starter prompts AND no herdr) — in that case set `DRIVE_MODE=skip_herdr` and fall through.

**Process (for each feature):**

1. **Validate feature name and compute worktree names:**
   ```bash
   # Feature name should be lowercase, alphanumeric with hyphens only
   if [[ ! "$FEATURE" =~ ^[a-z0-9-]+$ ]]; then
     echo "ERROR: Feature name must be lowercase alphanumeric with hyphens"
     exit 1
   fi

   # Compute WORKTREE_DIR and BRANCH using the same inference rules as cw_worktree_names():
   #   fix|bug|hotfix        -> type=fix
   #   research|spike|explore -> type=research
   #   chore|refactor|docs|build|ci -> type=chore
   #   (anything else)       -> type=feature
   # The matching leading keyword and its separating hyphen are stripped from the slug.
   # Repo is derived from the main worktree basename, sanitized to [a-z0-9-].
   if [[ "$FEATURE" =~ ^(fix|bug|hotfix)(-|$) ]]; then
     _TYPE="fix"; _SLUG="${FEATURE#"${BASH_REMATCH[1]}"}"; _SLUG="${_SLUG#-}"
   elif [[ "$FEATURE" =~ ^(research|spike|explore)(-|$) ]]; then
     _TYPE="research"; _SLUG="${FEATURE#"${BASH_REMATCH[1]}"}"; _SLUG="${_SLUG#-}"
   elif [[ "$FEATURE" =~ ^(chore|refactor|docs|build|ci)(-|$) ]]; then
     _TYPE="chore"; _SLUG="${FEATURE#"${BASH_REMATCH[1]}"}"; _SLUG="${_SLUG#-}"
   else
     _TYPE="feature"; _SLUG="$FEATURE"
   fi
   if [ -z "$_SLUG" ]; then
     echo "ERROR: slug is empty after keyword stripping (input: $FEATURE)"
     exit 1
   fi
   _MAIN_WT=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2; exit}')
   _REPO=$(basename "$_MAIN_WT" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')
   WORKTREE_DIR="${_TYPE}-${_REPO}-${_SLUG}"
   BRANCH="${_TYPE}/${_SLUG}"
   ```

2. **Ensure .worktrees is gitignored:**
   ```bash
   if ! git check-ignore -q .worktrees/ 2>/dev/null && ! grep -qx '.worktrees/' .gitignore 2>/dev/null; then
     echo ".worktrees/" >> .gitignore
     git add .gitignore
     git commit -m "chore: add .worktrees to gitignore"
   fi
   ```

3. **Check for existing worktree:**
   ```bash
   if [ -d ".worktrees/${WORKTREE_DIR}" ]; then
     echo "ERROR: Worktree already exists at .worktrees/${WORKTREE_DIR}"
     exit 1
   fi
   ```

4. **Check for existing branch:**
   ```bash
   if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
     echo "WARNING: Branch ${BRANCH} already exists"
     # Ask user: use existing branch or create fresh?
   fi
   ```

5. **Create worktree:**
   ```bash
   git worktree add ".worktrees/${WORKTREE_DIR}" -b "${BRANCH}"
   ```

6. **Configure isolated task list:**
   ```bash
   # WORKTREE_DIR=${_TYPE}-${_REPO}-${_SLUG} and BRANCH=${_TYPE}/${_SLUG} from step 1.
   # Create .claude directory if it doesn't exist
   mkdir -p ".worktrees/${WORKTREE_DIR}/.claude"

   # Create settings.local.json with task list ID matching the worktree directory name
   # Pre-approve workflow agent types so autonomous execution isn't interrupted
   cat > ".worktrees/${WORKTREE_DIR}/.claude/settings.local.json" << EOF
   {
     "env": {
       "CLAUDE_CODE_TASK_LIST_ID": "${WORKTREE_DIR}"
     },
     "permissions": {
       "allow": [
         "Skill({ skill: \"cw-research\" })",
         "Skill({ skill: \"cw-spec\" })",
         "Skill({ skill: \"cw-plan\" })",
         "Skill({ skill: \"cw-execute\" })",
         "Skill({ skill: \"cw-dispatch\" })",
         "Skill({ skill: \"cw-dispatch-team\" })",
         "Skill({ skill: \"cw-validate\" })",
         "Skill({ skill: \"cw-review\" })",
         "Skill({ skill: \"cw-review-team\" })",
         "Skill({ skill: \"cw-testing\" })",
         "Skill({ skill: \"cw-worktree\" })",
         "Task(claude-workflow:researcher)",
         "Task(claude-workflow:spec-writer)",
         "Task(claude-workflow:planner)",
         "Task(claude-workflow:implementer)",
         "Task(claude-workflow:validator)",
         "Task(claude-workflow:reviewer)",
         "Task(claude-workflow:test-executor)",
         "Task(claude-workflow:bug-fixer)"
       ]
     }
   }
   EOF
   ```

   This ensures Claude Code uses an isolated task list for this worktree - no shell setup required.

7. **Setup dependencies (auto-detect project type):**
   ```bash
   cd ".worktrees/${WORKTREE_DIR}"

   # Node.js
   if [ -f package.json ]; then
     npm install
   fi

   # Rust
   if [ -f Cargo.toml ]; then
     cargo build
   fi

   # Python
   if [ -f requirements.txt ]; then
     pip install -r requirements.txt
   elif [ -f pyproject.toml ]; then
     pip install -e .
   fi

   # Go
   if [ -f go.mod ]; then
     go mod download
   fi
   ```

8. **Run baseline tests:**
   ```bash
   # Detect and run tests
   if [ -f package.json ]; then
     npm test 2>/dev/null || echo "Note: Tests may need configuration"
   fi
   ```

9. **Invoke herdr integration (optional, silent on failure):**

   Read the cached `DRIVE_MODE` from per-invocation setup. `HERDR_OPEN_BIN` and `HERDR_AVAILABLE` were also resolved once in setup; this step uses those cached values. A failure on one worktree does not skip subsequent worktrees in a multi-create call.

   If `HERDR_AVAILABLE=0`, set `HERDR_EXIT=$HERDR_PROBE_EXIT` (preserves 2 vs 3 — see step 10 hint logic) and skip the helper entirely regardless of `DRIVE_MODE`. Fall through to legacy output in step 10.

   Otherwise dispatch on `DRIVE_MODE`:

   | `DRIVE_MODE` | Bash invocation |
   |---|---|
   | `starter` | `"$HERDR_OPEN_BIN" --prompt "$STARTER_PROMPT" ".worktrees/${WORKTREE_DIR}/" 2>/dev/null; HERDR_EXIT=$?` |
   | `autonomous` | `"$HERDR_OPEN_BIN" --prompt "$STARTER_PROMPT_GOAL" ".worktrees/${WORKTREE_DIR}/" 2>/dev/null; HERDR_EXIT=$?` |
   | `empty` | `"$HERDR_OPEN_BIN" ".worktrees/${WORKTREE_DIR}/" 2>/dev/null; HERDR_EXIT=$?` |
   | `skip_herdr` | `HERDR_EXIT=2` (do not invoke the helper) |

   When `DRIVE_MODE=starter` or `autonomous` and this specific feature has an empty `STARTER_PROMPT` / `STARTER_PROMPT_GOAL` (rare — only possible when the batch is mixed and the user picked a mode that fits *some* features), fall back to the `empty` invocation for this feature so the tab still opens.

   The helper has its own 5-second hard timeout on all herdr socket calls and exits 0 (success) / 2 (unavailable or opt-out) / 3 (daemon unreachable) / 4 (pane creation failed). Step 10's two branches are gated by `HERDR_EXIT=0` vs everything else.

10. **Report success:**

    The first "Next steps" line varies based on whether the herdr invocation (step 9) succeeded:

    **When `HERDR_EXIT=0` (herdr pane opened):**
    ```
    WORKTREE CREATED
    ================
    Path:   .worktrees/{WORKTREE_DIR}/
    Branch: {BRANCH}
    Task List: {WORKTREE_DIR} (via .claude/settings.local.json)
    Status: Ready for development

    Next steps (keep THIS session open as control center):
    1. Opened in herdr: workspace {repo-name} → tab {WORKTREE_DIR}
    2. Create spec: /cw-spec {feature-name}
    3. Plan and execute: /cw-plan → /cw-dispatch → /cw-validate
    4. Create PR: gh pr create (PR contains spec + implementation)
    5. Exit worktree session when done

    From THIS session you can:
      /cw-worktree list              # Check status of all worktrees
      /cw-worktree create <other>    # Create more worktrees
      /cw-worktree cleanup           # Remove merged worktrees

    To resume worktree work later:
      cd .worktrees/{WORKTREE_DIR} && claude
      (Tasks persist across sessions)

    To sync with main before PR (from worktree session):
      /cw-worktree sync {feature-name}
    ```

    **When `HERDR_EXIT!=0` (herdr unavailable or failed — legacy output, byte-identical to pre-herdr behavior):**

    When `HERDR_EXIT=3` (probe got past `command -v` but the socket is unreachable — i.e., herdr is installed but its daemon isn't running), note the daemon-down state in your summary so the user knows the integration is one daemon-start away. Otherwise (`HERDR_EXIT=2` — not installed or `CW_DISABLE_HERDR=1` — or `HERDR_EXIT=4` — pane-creation failure), no annotation. Then print the legacy block:

    ```
    WORKTREE CREATED
    ================
    Path:   .worktrees/{WORKTREE_DIR}/
    Branch: {BRANCH}
    Task List: {WORKTREE_DIR} (via .claude/settings.local.json)
    Status: Ready for development

    Next steps (keep THIS session open as control center):
    1. Open NEW terminal: cd .worktrees/{WORKTREE_DIR} && claude
    2. Create spec: /cw-spec {feature-name}
    3. Plan and execute: /cw-plan → /cw-dispatch → /cw-validate
    4. Create PR: gh pr create (PR contains spec + implementation)
    5. Exit worktree session when done

    From THIS session you can:
      /cw-worktree list              # Check status of all worktrees
      /cw-worktree create <other>    # Create more worktrees
      /cw-worktree cleanup           # Remove merged worktrees

    To resume worktree work later:
      cd .worktrees/{WORKTREE_DIR} && claude
      (Tasks persist across sessions)

    To sync with main before PR (from worktree session):
      /cw-worktree sync {feature-name}
    ```

    The helper's stderr is suppressed (`2>/dev/null`). For diagnosis run `cw-herdr-open --probe; echo $?` directly — see SKILL.md "Diagnosing the herdr integration".

11. **Include starter prompt (only when herdr did not forward it):**

    When step 9 forwarded the prompt (`HERDR_EXIT=0` and `DRIVE_MODE ∈ {starter, autonomous}`), the spawned claude session already has it and nothing needs to be printed here.

    Print the copy-paste block only when **both** hold:
    - `HERDR_EXIT!=0` (herdr unavailable, `DRIVE_MODE=skip_herdr`, or the helper failed), **and**
    - A starter prompt was constructed for this feature (`STARTER_PROMPT` non-empty, or `STARTER_PROMPT_GOAL` non-empty when `DRIVE_MODE=autonomous`).

    Use `STARTER_PROMPT_GOAL` for the body when `DRIVE_MODE=autonomous`; otherwise use `STARTER_PROMPT`.

    ```
    STARTER PROMPT (copy into worktree session)
    ═══════════════════════════════════════════

    {STARTER_PROMPT or STARTER_PROMPT_GOAL verbatim — see SKILL.md
     "Starter Prompt Generation" and "Autonomous variant" for templates}
    ```

---

## list

**Process:**

1. **Get worktree list:**
   ```bash
   git worktree list
   ```

2. **Enhance with status info:**
   For each worktree in `.worktrees/`:
   - Get branch name
   - Check for uncommitted changes
   - Count commits ahead/behind main
   - Check if associated spec exists

3. **Output format:**
   ```
   ACTIVE WORKTREES
   ================
   PATH                                    BRANCH                    STATUS
   --------------------------------------- ------------------------- ------------------
   .                                       main                      (project root)
   .worktrees/feature-myrepo-auth          feature/myrepo-auth       3 ahead, clean
   .worktrees/fix-myrepo-billing           fix/myrepo-billing        1 ahead, modified
   .worktrees/feature-auth                 feature/auth              5 ahead, clean

   Specs in progress:
   - 01-spec-auth → .worktrees/feature-myrepo-auth
   - 02-spec-billing → .worktrees/fix-myrepo-billing
   ```

---

## status

**Process:**

1. **Resolve worktree directory:**
   Look up the actual worktree directory under `.worktrees/` by matching against `git worktree list` — do not assume a `feature-` prefix.
   ```bash
   # Find the worktree directory for the given name, regardless of prefix
   WORKTREE_DIR=$(git worktree list --porcelain | awk '/^worktree /{print $2}' | grep "/\.worktrees/" \
     | while read -r _wt; do _b=$(basename "$_wt"); case "$_b" in "$FEATURE"|*-"$FEATURE") echo ".worktrees/$_b"; break;; esac; done)
   if [ -z "$WORKTREE_DIR" ] || [ ! -d "$WORKTREE_DIR" ]; then
     echo "ERROR: No worktree found for '${FEATURE}'"
     echo "Run /cw-worktree list to see available worktrees"
     exit 1
   fi
   ```

2. **Gather status information:**
   ```bash
   cd "$WORKTREE_DIR"

   # Branch info
   git branch -vv

   # Commits ahead of main
   git log main..HEAD --oneline

   # Working tree status
   git status --short

   # Recent commits
   git log -5 --oneline
   ```

3. **Check for associated spec:**
   ```bash
   # Look for spec matching feature name
   ls -d docs/specs/*-spec-*${FEATURE}*/ 2>/dev/null
   ```

4. **Output format:**
   ```
   WORKTREE STATUS: {feature-name}
   ================================
   Path:   {resolved-worktree-dir}/
   Branch: {branch-name}

   Commits ahead of main: 5
     abc1234 feat(auth): add login endpoint
     def5678 feat(auth): add token validation
     ...

   Working tree: clean | X modified files

   Associated spec: docs/specs/01-spec-auth/

   Ready to merge: Yes | No (uncommitted changes)
   ```

---

## merge

**Process:**

1. **Pre-merge validation:**
   ```bash
   # Verify in project root
   if [ ! -d ".git" ]; then
     echo "ERROR: Must run from project root"
     exit 1
   fi

   # Resolve worktree directory — match against git worktree list, not a fixed prefix
   WORKTREE_DIR=$(git worktree list --porcelain | awk '/^worktree /{print $2}' | grep "/\.worktrees/" \
     | while read -r _wt; do _b=$(basename "$_wt"); case "$_b" in "$FEATURE"|*-"$FEATURE") echo ".worktrees/$_b"; break;; esac; done)
   if [ -z "$WORKTREE_DIR" ] || [ ! -d "$WORKTREE_DIR" ]; then
     echo "ERROR: No worktree found for '${FEATURE}'"
     exit 1
   fi

   # Check for uncommitted changes in worktree
   cd "$WORKTREE_DIR"
   if [ -n "$(git status --porcelain)" ]; then
     echo "ERROR: Worktree has uncommitted changes"
     echo "Commit or stash changes before merging"
     exit 1
   fi
   ```

2. **Run tests in feature worktree:**
   ```bash
   cd "$WORKTREE_DIR"

   # Auto-detect and run tests
   if [ -f package.json ]; then
     npm test
   elif [ -f Cargo.toml ]; then
     cargo test
   elif [ -f go.mod ]; then
     go test ./...
   elif [ -f pytest.ini ] || [ -f pyproject.toml ]; then
     pytest
   fi

   if [ $? -ne 0 ]; then
     echo "ERROR: Tests failing in worktree for '${FEATURE}'"
     echo "Fix tests before merging"
     exit 1
   fi
   ```

3. **Offer rebase option if main has moved:**
   ```bash
   cd "$WORKTREE_DIR"
   BEHIND=$(git rev-list HEAD..main --count)

   if [ "$BEHIND" -gt 0 ]; then
     echo "Main has $BEHIND new commits since branch creation"
     # Use AskUserQuestion to offer rebase
   fi
   ```

   Use AskUserQuestion:
   ```
   AskUserQuestion({
     questions: [{
       question: "Main branch has new commits. How should we proceed?",
       header: "Rebase",
       options: [
         { label: "Rebase first (Recommended)", description: "Rebase feature branch on main, then merge" },
         { label: "Merge directly", description: "Create merge commit without rebasing" }
       ],
       multiSelect: false
     }]
   })
   ```

4. **Perform merge:**
   ```bash
   # Return to project root
   cd "${PROJECT_ROOT}"

   # Ensure on main and up to date
   git checkout main
   git pull origin main 2>/dev/null || true  # May not have remote

   # Read the branch name from the resolved worktree (works for any prefix)
   BRANCH=$(cd "$WORKTREE_DIR" && git branch --show-current)

   # Merge the feature branch
   git merge "${BRANCH}" --no-ff -m "Merge ${BRANCH}: [description from spec or commits]"
   ```

5. **Run full test suite:**
   ```bash
   # Run tests in main
   if [ -f package.json ]; then
     npm test
   fi

   if [ $? -ne 0 ]; then
     echo "ERROR: Tests failing after merge"
     echo "Resolve conflicts and fix tests"
     git merge --abort 2>/dev/null || true
     exit 1
   fi
   ```

6. **Cleanup (with confirmation):**
   ```
   AskUserQuestion({
     questions: [{
       question: "Merge successful! Clean up the feature branch and worktree?",
       header: "Cleanup",
       options: [
         { label: "Yes, clean up (Recommended)", description: "Delete branch and remove worktree" },
         { label: "Keep for now", description: "Leave branch and worktree in place" }
       ],
       multiSelect: false
     }]
   })
   ```

   If cleanup confirmed:
   ```bash
   git branch -d "${BRANCH}"
   git worktree remove "${WORKTREE_DIR}"
   ```

7. **Report success:**
   ```
   MERGE COMPLETE
   ==============
   Branch: {branch-name} → main
   Commit: {merge-commit-sha}

   Cleanup: Completed | Skipped

   Next steps:
   - Review changes: git log -1
   - Push to remote: git push origin main
   ```

---

## sync

**Process:**

1. **Resolve worktree directory:**
   ```bash
   # Find the worktree directory by name, regardless of prefix
   WORKTREE_DIR=$(git worktree list --porcelain | awk '/^worktree /{print $2}' | grep "/\.worktrees/" \
     | while read -r _wt; do _b=$(basename "$_wt"); case "$_b" in "$FEATURE"|*-"$FEATURE") echo ".worktrees/$_b"; break;; esac; done)
   if [ -z "$WORKTREE_DIR" ] || [ ! -d "$WORKTREE_DIR" ]; then
     echo "ERROR: No worktree found for feature '${FEATURE}'"
     echo "Run /cw-worktree list to see available worktrees"
     exit 1
   fi
   ```

2. **Check for uncommitted changes:**
   ```bash
   cd "$WORKTREE_DIR"
   if [ -n "$(git status --porcelain)" ]; then
     echo "ERROR: Worktree has uncommitted changes"
     echo "Commit or stash changes before syncing"
     exit 1
   fi
   ```

3. **Fetch and check if sync needed:**
   ```bash
   git fetch origin main
   BEHIND=$(git rev-list HEAD..origin/main --count)

   if [ "$BEHIND" -eq 0 ]; then
     echo "Already up to date with main"
     exit 0
   fi

   echo "Main has $BEHIND new commits"
   ```

4. **Perform rebase:**
   ```bash
   git rebase origin/main
   ```

5. **Handle conflicts if any:**
   If rebase has conflicts:
   ```
   SYNC CONFLICT
   =============
   Conflicts detected during rebase.

   Conflicting files:
   - {list of files}

   To resolve:
   1. Edit conflicting files
   2. git add {resolved-files}
   3. git rebase --continue

   To abort:
     git rebase --abort
   ```

6. **Report success:**
   ```
   SYNC COMPLETE
   =============
   Branch: {branch-name}
   Rebased on: origin/main
   Commits replayed: {count}

   The feature branch is now up to date with main.
   Ready for PR: gh pr create
   ```

---

## open

Retrospectively attaches a herdr pane to an existing worktree. If a matching workspace and claude pane already exist (matched on both cwd and command), the workspace is focused rather than spawning a duplicate. When herdr is unavailable the command prints legacy manual instructions and exits 0.

**Process:**

1. **Resolve worktree directory:**
   ```bash
   FEATURE="$1"
   # Resolve the actual worktree directory — match against git worktree list,
   # not a hardcoded feature- prefix, so both new {type}-{repo}-{slug} and
   # legacy feature-* directories are found.
   WORKTREE_DIR=$(git worktree list --porcelain | awk '/^worktree /{print $2}' | grep "/\.worktrees/" \
     | while read -r _wt; do _b=$(basename "$_wt"); case "$_b" in "$FEATURE"|*-"$FEATURE") echo ".worktrees/$_b"; break;; esac; done)
   if [ -z "$WORKTREE_DIR" ] || [ ! -d "$WORKTREE_DIR" ]; then
     echo "ERROR: No worktree found for '${FEATURE}'" >&2
     echo "Run /cw-worktree list to see available worktrees." >&2
     exit 1
   fi
   ```

2. **Validate and read branch:**
   ```bash
   BRANCH=$(cd "$WORKTREE_DIR" && git branch --show-current 2>/dev/null || echo "unknown")
   ```

3. **Resolve helper path and invoke with --focus-if-exists:**

   Helper lookup uses the same three-step resolution as the `create` command — PATH first (marketplace installs), then `CLAUDE_PLUGIN_ROOT`, then the git top-level fallback (plugin source checkout only).

   ```bash
   HERDR_OPEN_BIN="$(command -v cw-herdr-open 2>/dev/null || true)"
   if [ -z "$HERDR_OPEN_BIN" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
     HERDR_OPEN_BIN="$CLAUDE_PLUGIN_ROOT/bin/cw-herdr-open"
   fi
   if [ -z "$HERDR_OPEN_BIN" ] || [ ! -x "$HERDR_OPEN_BIN" ]; then
     HERDR_OPEN_BIN="$(git rev-parse --show-toplevel 2>/dev/null)/bin/cw-herdr-open"
   fi

   HERDR_EXIT=2  # default: treat as unavailable
   if [ -x "$HERDR_OPEN_BIN" ]; then
     "$HERDR_OPEN_BIN" --focus-if-exists "${WORKTREE_DIR}/" 2>/dev/null
     HERDR_EXIT=$?
   fi
   ```

   The helper's layout is **one workspace per repo, one tab per worktree, one claude pane per tab**:
   - The workspace label is the repo basename (derived from `git rev-parse --git-common-dir`).
   - The tab label is the worktree basename (e.g. `feature-auth`).
   - Look up an existing workspace by repo name; if absent, create it (the workspace's default tab is reused as this worktree's tab — no empty placeholder).
   - Look up an existing tab in that workspace by worktree-basename label; if absent, create it.
   - If the tab's pane is already running `claude` at the matching cwd: focus workspace + tab and exit 0 without spawning a duplicate.
   - Otherwise: run `claude` in the tab's existing root pane via `herdr pane run`.
   - `--focus-if-exists` is accepted for backward compatibility; the reuse-on-duplicate behaviour above runs unconditionally.

4. **Report result:**

   **When `HERDR_EXIT=0` (herdr pane opened or focused):**
   ```
   WORKTREE OPEN
   =============
   Path:   {resolved-worktree-dir}/
   Branch: {branch-name}

   Opened (or focused) in herdr: workspace {repo-name} → tab {worktree-basename}

   To resume work in the terminal:
     cd {resolved-worktree-dir} && claude
   ```

   **When `HERDR_EXIT!=0` (herdr unavailable or CW_DISABLE_HERDR set — legacy output):**

   When `HERDR_EXIT=3` (herdr is installed but its daemon isn't running), note the daemon-down state in your summary so the user knows the integration is one daemon-start away. Otherwise (`HERDR_EXIT=2`), no annotation. Then print the legacy block:

   ```
   WORKTREE OPEN
   =============
   Path:   {resolved-worktree-dir}/
   Branch: {branch-name}

   Open a terminal and run:
     cd {resolved-worktree-dir} && claude
   ```

   The helper's stderr is suppressed (`2>/dev/null`). For diagnosis run `cw-herdr-open --probe; echo $?` directly — see SKILL.md "Diagnosing the herdr integration".

---

## cleanup

**Process:**

1. **Find all worktrees:**
   ```bash
   git worktree list --porcelain
   ```

2. **Identify candidates for cleanup:**
   - Worktrees with no uncommitted changes whose branches are merged to main
   - Worktrees whose branches no longer exist
   - Any directory under `.worktrees/*` that is not registered in `git worktree list` (orphaned directories)
   - Matches both new `{type}-{repo}-{slug}` and legacy `feature-*` naming

3. **Present cleanup options:**
   ```
   WORKTREE CLEANUP
   ================

   Merged (safe to remove):
   - .worktrees/feature-myrepo-auth (branch merged to main)
   - .worktrees/feature-login (branch merged to main)

   Orphaned (directories without worktree):
   - .worktrees/fix-myrepo-old (no git worktree entry)

   Active (will NOT be removed):
   - .worktrees/fix-myrepo-billing (3 commits ahead of main)
   ```

4. **Confirm cleanup:**
   ```
   AskUserQuestion({
     questions: [{
       question: "Remove the merged/orphaned worktrees listed above?",
       header: "Confirm",
       options: [
         { label: "Yes, clean up", description: "Remove merged and orphaned worktrees" },
         { label: "No, keep all", description: "Don't remove any worktrees" }
       ],
       multiSelect: false
     }]
   })
   ```

5. **Perform cleanup:**
   ```bash
   # For each merged worktree
   git worktree remove ".worktrees/${WORKTREE_DIR}"
   git branch -d "${BRANCH}" 2>/dev/null || true

   # For orphaned directories
   rm -rf ".worktrees/${WORKTREE_DIR}"
   ```

6. **Prune worktree references:**
   ```bash
   git worktree prune
   ```
