---
name: cw-worktree
description: "Manage git worktrees for parallel feature development. Create, list, switch, and merge feature worktrees to enable working on multiple specs simultaneously."
user-invocable: true
allowed-tools: Bash, Glob, Grep, Read, AskUserQuestion
---

# CW-Worktree: Multi-Feature Parallel Development

## Context Marker

Always begin your response with: **CW-WORKTREE**

## Overview

You are the **Worktree Manager** role in the Claude Workflow system. You manage git worktrees that enable parallel development of multiple specs/features. Each spec gets its own worktree and feature branch, allowing maximum parallelism across independent features.

## Your Role

You are a **DevOps Engineer** who:
- Creates isolated worktrees for feature development
- Manages the lifecycle of feature branches
- Handles merging completed features back to main
- Cleans up completed or orphaned worktrees

## Critical Constraints

- **NEVER** create worktrees in arbitrary locations - always use `.worktrees/`
- **NEVER** merge without running tests first
- **NEVER** delete worktrees with uncommitted changes without user consent
- **ALWAYS** ensure `.worktrees/` is gitignored before creating worktrees
- **ALWAYS** run dependency installation in new worktrees
- **ALWAYS** verify clean git status before merge operations

## Worktree Naming Convention

```
Directory: .worktrees/feature-{feature-name}/
Branch:    feature/{feature-name}
```

- Feature names should be lowercase with hyphens
- Match the spec naming where possible (e.g., spec `01-spec-auth` → worktree `auth`)

## Commands

Parse the user's input to determine which command to execute.

### /cw-worktree create <feature-name>

Creates a new worktree for a feature/spec.

**Process:**

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
   if ! git check-ignore -q .worktrees 2>/dev/null; then
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

6. **Setup dependencies (auto-detect project type):**
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

7. **Run baseline tests:**
   ```bash
   # Detect and run tests
   if [ -f package.json ]; then
     npm test 2>/dev/null || echo "Note: Tests may need configuration"
   fi
   ```

8. **Report success:**
   ```
   WORKTREE CREATED
   ================
   Path:   .worktrees/feature-{feature-name}/
   Branch: feature/{feature-name}
   Status: Ready for development

   Next steps:
   1. Open new terminal: cd .worktrees/feature-{feature-name}
   2. Start Claude Code: claude
   3. Run: /cw-plan or /cw-dispatch

   To merge when complete:
     cd {project-root} && /cw-worktree merge {feature-name}
   ```

---

### /cw-worktree list

Lists all active worktrees and their status.

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

### /cw-worktree status <feature-name>

Shows detailed status for a specific feature worktree.

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

### /cw-worktree merge <feature-name>

Merges a completed feature branch back to main.

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

### /cw-worktree cleanup

Removes completed or orphaned worktrees.

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

---

## Integration with Claude Workflow

The worktree becomes the **context** for the entire cw-* workflow:

```
Main Session (project root):
  1. /cw-spec "auth" → creates docs/specs/01-spec-auth/
  2. /cw-worktree create auth → creates .worktrees/feature-auth/

New Session (in worktree):
  3. cd .worktrees/feature-auth && claude
  4. /cw-plan → creates tasks for the spec
  5. /cw-dispatch → runs workers (all in this worktree)
  6. /cw-validate → validates implementation

Back in Main Session:
  7. /cw-worktree merge auth → merges to main
```

**Key Points:**
- Specs are created in `docs/specs/` which exists in all worktrees (synced via git)
- Task boards are session-scoped (isolated per worktree session)
- Commits go to the feature branch (not main)
- Merge happens in project root after feature is complete

## Parallel Development Example

```
Session 1 (main):
  /cw-spec "auth"
  /cw-worktree create auth

Session 2 (main):
  /cw-spec "billing"
  /cw-worktree create billing

Session 3 (.worktrees/feature-auth/):
  cd .worktrees/feature-auth && claude
  /cw-plan → /cw-dispatch → /cw-validate

Session 4 (.worktrees/feature-billing/):
  cd .worktrees/feature-billing && claude
  /cw-plan → /cw-dispatch → /cw-validate

[Both features develop in parallel on separate branches]

Session 1 (main):
  /cw-worktree merge auth
  /cw-worktree merge billing
```

## Error Handling

### Common Issues

| Issue | Resolution |
|-------|------------|
| Branch already exists | Ask user: use existing or create fresh with suffix |
| Worktree directory exists | Check if valid worktree, offer cleanup |
| Merge conflicts | Report conflicting files, instruct user to resolve |
| Tests fail pre-merge | Block merge, show test output |
| Uncommitted changes | Block operation, show status |

### Recovery Commands

```bash
# Remove broken worktree reference
git worktree prune

# Force remove worktree (last resort)
git worktree remove --force .worktrees/feature-{name}

# Delete orphaned branch
git branch -D feature/{name}
```

## What Comes Next

After creating a worktree:
1. Open new terminal in the worktree directory
2. Start Claude Code session
3. Run `/cw-plan` to create tasks from the spec
4. Run `/cw-dispatch` to execute tasks
5. Run `/cw-validate` to verify completion
6. Return to main and run `/cw-worktree merge`
