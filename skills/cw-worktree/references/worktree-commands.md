# Worktree Command Implementations

Detailed process steps for each `/cw-worktree` command. Referenced from [SKILL.md](../SKILL.md).

---

## create

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
         "Skill(cw-research)",
         "Skill(cw-spec)",
         "Skill(cw-plan)",
         "Skill(cw-execute)",
         "Skill(cw-dispatch)",
         "Skill(cw-dispatch-team)",
         "Skill(cw-validate)",
         "Skill(cw-review)",
         "Skill(cw-review-team)",
         "Skill(cw-testing)",
         "Skill(cw-worktree)",
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

9. **Report success:**
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

10. **Include starter prompt (if context was gathered):**

    If the feature was scoped during discovery (components identified, requirements discussed), include a starter prompt the user can paste into the worktree session. Use plain text for easy copying:

    ```
    STARTER PROMPT (copy into worktree session)
    ═══════════════════════════════════════════

    Build {feature-name}.

    {Brief description of what the feature does}

    Components/files to create:
    - {Component1}: {purpose}
    - {Component2}: {purpose}

    {Any routes, APIs, or patterns to follow}

    Run: /cw-spec {feature-name}
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
