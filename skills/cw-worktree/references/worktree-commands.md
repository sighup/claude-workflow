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

**Process (for each feature):**

1. **Validate feature name:**
   ```bash
   # Feature name should be lowercase, alphanumeric with hyphens only
   if [[ ! "$FEATURE" =~ ^[a-z0-9-]+$ ]]; then
     echo "ERROR: Feature name must be lowercase alphanumeric with hyphens"
     exit 1
   fi
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
   if [ -d ".worktrees/feature-${FEATURE}" ]; then
     echo "ERROR: Worktree already exists at .worktrees/feature-${FEATURE}"
     exit 1
   fi
   ```

4. **Check for existing branch:**
   ```bash
   if git show-ref --verify --quiet "refs/heads/feature/${FEATURE}"; then
     echo "WARNING: Branch feature/${FEATURE} already exists"
     # Ask user: use existing branch or create fresh?
   fi
   ```

5. **Create worktree:**
   ```bash
   git worktree add ".worktrees/feature-${FEATURE}" -b "feature/${FEATURE}"
   ```

6. **Configure isolated task list:**
   ```bash
   # Determine worktree directory name (e.g., "feature-auth", "bugfix-login")
   WORKTREE_DIR="feature-${FEATURE}"

   # Create .claude directory if it doesn't exist
   mkdir -p ".worktrees/${WORKTREE_DIR}/.claude"

   # Create settings.local.json with task list ID matching directory name
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
   cd ".worktrees/feature-${FEATURE}"

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

   After the worktree and task list are configured, attempt to open a herdr pane for this worktree. `HERDR_OPEN_BIN` and `HERDR_AVAILABLE` were resolved once in the per-invocation setup above; this step uses those cached values. A failure on one worktree does not skip subsequent worktrees in a multi-create call.

   **Decide invocation shape** based on `$HERDR_AVAILABLE` and whether a starter prompt was constructed (the probe runs only once per multi-create — see per-invocation setup above; before forwarding a starter prompt, only the `AskUserQuestion` confirmation runs per worktree).

   - `HERDR_AVAILABLE=0` → set `HERDR_EXIT=$HERDR_PROBE_EXIT` (preserves 2 vs 3 — see step 10 hint logic) and skip the helper entirely. Fall through to legacy output in step 10.
   - `HERDR_AVAILABLE=1` and no starter prompt → invoke without `--prompt`:
     ```bash
     "$HERDR_OPEN_BIN" ".worktrees/feature-${FEATURE}/" 2>/dev/null
     HERDR_EXIT=$?
     ```
   - `HERDR_AVAILABLE=1` and starter prompt available → use `AskUserQuestion` to confirm before forwarding (the question is rendered by Claude, not Bash):

     ```
     AskUserQuestion({
       questions: [{
         question: "Open feature-{name} in herdr with this kickoff?",
         header: "Herdr",
         options: [
           { label: "Yes, start with this prompt (Recommended)",
             description: "Spawn a herdr pane running claude with the prompt as first message",
             preview: "<STARTER_PROMPT verbatim>" },
           { label: "Open empty session",
             description: "Spawn a herdr pane running claude with no auto-prompt" },
           { label: "Don't open in herdr",
             description: "Skip herdr; the worktree is still created" }
         ],
         multiSelect: false
       }]
     })
     ```

     Map the answer to a Bash invocation:
     - **Recommended** (or **Other** with edited text) → `"$HERDR_OPEN_BIN" --prompt "$STARTER_PROMPT" ".worktrees/feature-${FEATURE}/" 2>/dev/null` then `HERDR_EXIT=$?`
     - **Open empty session** → `"$HERDR_OPEN_BIN" ".worktrees/feature-${FEATURE}/" 2>/dev/null` then `HERDR_EXIT=$?`
     - **Don't open in herdr** → set `HERDR_EXIT=2`, do not invoke the helper

   The helper has its own 5-second hard timeout on all herdr socket calls and exits 0 (success) / 2 (unavailable or opt-out) / 3 (daemon unreachable) / 4 (pane creation failed). Step 10's two branches are gated by `HERDR_EXIT=0` vs everything else.

10. **Report success:**

    The first "Next steps" line varies based on whether the herdr invocation (step 9) succeeded:

    **When `HERDR_EXIT=0` (herdr pane opened):**
    ```
    WORKTREE CREATED
    ================
    Path:   .worktrees/feature-{feature-name}/
    Branch: feature/{feature-name}
    Task List: feature-{feature-name} (via .claude/settings.local.json)
    Status: Ready for development

    Next steps (keep THIS session open as control center):
    1. Opened in herdr workspace: feature-{feature-name}
    2. Create spec: /cw-spec {feature-name}
    3. Plan and execute: /cw-plan → /cw-dispatch → /cw-validate
    4. Create PR: gh pr create (PR contains spec + implementation)
    5. Exit worktree session when done

    From THIS session you can:
      /cw-worktree list              # Check status of all worktrees
      /cw-worktree create <other>    # Create more worktrees
      /cw-worktree cleanup           # Remove merged worktrees

    To resume worktree work later:
      cd .worktrees/feature-{feature-name} && claude
      (Tasks persist across sessions)

    To sync with main before PR (from worktree session):
      /cw-worktree sync {feature-name}
    ```

    **When `HERDR_EXIT!=0` (herdr unavailable or failed — legacy output, byte-identical to pre-herdr behavior):**

    When `HERDR_EXIT=3` (probe got past `command -v` but the socket is unreachable — i.e., herdr is installed but its daemon isn't running), note the daemon-down state in your summary so the user knows the integration is one daemon-start away. Otherwise (`HERDR_EXIT=2` — not installed or `CW_DISABLE_HERDR=1` — or `HERDR_EXIT=4` — pane-creation failure), no annotation. Then print the legacy block:

    ```
    WORKTREE CREATED
    ================
    Path:   .worktrees/feature-{feature-name}/
    Branch: feature/{feature-name}
    Task List: feature-{feature-name} (via .claude/settings.local.json)
    Status: Ready for development

    Next steps (keep THIS session open as control center):
    1. Open NEW terminal: cd .worktrees/feature-{feature-name} && claude
    2. Create spec: /cw-spec {feature-name}
    3. Plan and execute: /cw-plan → /cw-dispatch → /cw-validate
    4. Create PR: gh pr create (PR contains spec + implementation)
    5. Exit worktree session when done

    From THIS session you can:
      /cw-worktree list              # Check status of all worktrees
      /cw-worktree create <other>    # Create more worktrees
      /cw-worktree cleanup           # Remove merged worktrees

    To resume worktree work later:
      cd .worktrees/feature-{feature-name} && claude
      (Tasks persist across sessions)

    To sync with main before PR (from worktree session):
      /cw-worktree sync {feature-name}
    ```

    The helper's stderr is suppressed (`2>/dev/null`). For diagnosis run `cw-herdr-open --probe; echo $?` directly — see SKILL.md "Diagnosing the herdr integration".

11. **Include starter prompt (only when herdr did not forward it):**

    When `HERDR_EXIT=0` and the user chose "Yes, start with this prompt" in step 9, the prompt was already forwarded to the spawned claude session via `--prompt` and does NOT need to be printed here.

    Print the copy-paste block only when one of the following holds:
    - `HERDR_EXIT!=0` (herdr unavailable, the user picked "Don't open in herdr", or the helper failed), **and**
    - A starter prompt was constructed in step 9.

    ```
    STARTER PROMPT (copy into worktree session)
    ═══════════════════════════════════════════

    {STARTER_PROMPT verbatim — see SKILL.md "Starter Prompt Generation"
     for the research-mode and spec-mode templates}
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
   PATH                          BRANCH              STATUS
   ----------------------------- ------------------- ------------------
   .                             main                (project root)
   .worktrees/feature-auth       feature/auth        3 ahead, clean
   .worktrees/feature-billing    feature/billing     1 ahead, modified
   .worktrees/feature-search     feature/search      5 ahead, clean

   Specs in progress:
   - 01-spec-auth → .worktrees/feature-auth
   - 02-spec-billing → .worktrees/feature-billing
   ```

---

## status

**Process:**

1. **Validate worktree exists:**
   ```bash
   if [ ! -d ".worktrees/feature-${FEATURE}" ]; then
     echo "ERROR: No worktree found for feature '${FEATURE}'"
     echo "Run /cw-worktree list to see available worktrees"
     exit 1
   fi
   ```

2. **Gather status information:**
   ```bash
   cd ".worktrees/feature-${FEATURE}"

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
   Path:   .worktrees/feature-{feature-name}/
   Branch: feature/{feature-name}

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

   # Verify worktree exists
   if [ ! -d ".worktrees/feature-${FEATURE}" ]; then
     echo "ERROR: No worktree found for '${FEATURE}'"
     exit 1
   fi

   # Check for uncommitted changes in worktree
   cd ".worktrees/feature-${FEATURE}"
   if [ -n "$(git status --porcelain)" ]; then
     echo "ERROR: Worktree has uncommitted changes"
     echo "Commit or stash changes before merging"
     exit 1
   fi
   ```

2. **Run tests in feature worktree:**
   ```bash
   cd ".worktrees/feature-${FEATURE}"

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
     echo "ERROR: Tests failing in feature/${FEATURE}"
     echo "Fix tests before merging"
     exit 1
   fi
   ```

3. **Offer rebase option if main has moved:**
   ```bash
   cd ".worktrees/feature-${FEATURE}"
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

   # Merge feature branch
   git merge "feature/${FEATURE}" --no-ff -m "Merge feature/${FEATURE}: [description from spec or commits]"
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
   git branch -d "feature/${FEATURE}"
   git worktree remove ".worktrees/feature-${FEATURE}"
   ```

7. **Report success:**
   ```
   MERGE COMPLETE
   ==============
   Branch: feature/{feature-name} → main
   Commit: {merge-commit-sha}

   Cleanup: Completed | Skipped

   Next steps:
   - Review changes: git log -1
   - Push to remote: git push origin main
   ```

---

## sync

**Process:**

1. **Validate worktree exists:**
   ```bash
   if [ ! -d ".worktrees/feature-${FEATURE}" ]; then
     echo "ERROR: No worktree found for feature '${FEATURE}'"
     echo "Run /cw-worktree list to see available worktrees"
     exit 1
   fi
   ```

2. **Check for uncommitted changes:**
   ```bash
   cd ".worktrees/feature-${FEATURE}"
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
   Branch: feature/{feature-name}
   Rebased on: origin/main
   Commits replayed: {count}

   The feature branch is now up to date with main.
   Ready for PR: gh pr create
   ```

---

## open

Retrospectively attaches a herdr pane to an existing worktree. If a matching workspace and claude pane already exist (matched on both cwd and command), the workspace is focused rather than spawning a duplicate. When herdr is unavailable the command prints legacy manual instructions and exits 0.

**Process:**

1. **Parse feature name:**
   ```bash
   FEATURE="$1"
   WORKTREE_DIR=".worktrees/feature-${FEATURE}"
   ```

2. **Validate the worktree exists:**
   ```bash
   if [ ! -d "$WORKTREE_DIR" ]; then
     echo "ERROR: No worktree found for feature '${FEATURE}' (expected: ${WORKTREE_DIR})" >&2
     echo "Run /cw-worktree list to see available worktrees." >&2
     exit 1
   fi
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

   The `--focus-if-exists` flag instructs the helper to:
   - Look up the herdr workspace whose label matches the worktree basename (`feature-<name>`).
   - Query `herdr agent list` to find any existing pane running `claude` with `cwd` equal to the absolute worktree path.
   - If found: focus the workspace via `herdr workspace focus <workspace_id>` and exit 0 without creating a duplicate.
   - If the workspace exists but no matching pane is present: create a new pane in that workspace.
   - If neither workspace nor pane exists: create both (same behaviour as `create`).

4. **Report result:**

   **When `HERDR_EXIT=0` (herdr pane opened or focused):**
   ```
   WORKTREE OPEN
   =============
   Path:   .worktrees/feature-{feature-name}/
   Branch: feature/{feature-name}

   Opened (or focused) in herdr workspace: feature-{feature-name}

   To resume work in the terminal:
     cd .worktrees/feature-{feature-name} && claude
   ```

   **When `HERDR_EXIT!=0` (herdr unavailable or CW_DISABLE_HERDR set — legacy output):**

   When `HERDR_EXIT=3` (herdr is installed but its daemon isn't running), note the daemon-down state in your summary so the user knows the integration is one daemon-start away. Otherwise (`HERDR_EXIT=2`), no annotation. Then print the legacy block:

   ```
   WORKTREE OPEN
   =============
   Path:   .worktrees/feature-{feature-name}/
   Branch: feature/{feature-name}

   Open a terminal and run:
     cd .worktrees/feature-{feature-name} && claude
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
   - Worktrees in `.worktrees/` that are not in git worktree list (orphaned directories)

3. **Present cleanup options:**
   ```
   WORKTREE CLEANUP
   ================

   Merged (safe to remove):
   - .worktrees/feature-auth (branch merged to main)
   - .worktrees/feature-login (branch merged to main)

   Orphaned (directories without worktree):
   - .worktrees/feature-old (no git worktree entry)

   Active (will NOT be removed):
   - .worktrees/feature-billing (3 commits ahead of main)
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
   git worktree remove ".worktrees/feature-${FEATURE}"
   git branch -d "feature/${FEATURE}" 2>/dev/null || true

   # For orphaned directories
   rm -rf ".worktrees/feature-${FEATURE}"
   ```

6. **Prune worktree references:**
   ```bash
   git worktree prune
   ```
