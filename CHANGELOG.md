# CHANGELOG

<!-- version list -->

## v3.7.0 (2026-07-06)

### Features

- **cw-research,cw-spec**: Add blindspot section, reorder questions by blast radius
  ([#45](https://github.com/sighup/claude-workflow/pull/45),
  [`e690704`](https://github.com/sighup/claude-workflow/commit/e690704d742fd7d0e15deb174a65df6a80ab6d5e))


## v3.6.0 (2026-07-06)

### Documentation

- Language consistency, voice, and accuracy fixes
  ([#42](https://github.com/sighup/claude-workflow/pull/42),
  [`fa5e43c`](https://github.com/sighup/claude-workflow/commit/fa5e43cc04cdf79e52ea933bb345f342b4509e2a))

### Features

- **cw-explain**: Publish artifacts via Claude Code Artifact tool
  ([#44](https://github.com/sighup/claude-workflow/pull/44),
  [`b703572`](https://github.com/sighup/claude-workflow/commit/b703572bbe8206497ee2a50eea99d089a80aff76))


## v3.5.0 (2026-07-04)

### Features

- **hooks**: Name worktree sessions from task-list ID
  ([#41](https://github.com/sighup/claude-workflow/pull/41),
  [`4bc3ad3`](https://github.com/sighup/claude-workflow/commit/4bc3ad3db398b1a2e2545b2656226357a964ec32))


## v3.4.0 (2026-07-02)

### Features

- **skills**: Add cw-explain interactive HTML change explainer
  ([#40](https://github.com/sighup/claude-workflow/pull/40),
  [`b937018`](https://github.com/sighup/claude-workflow/commit/b937018e98a719a14df22d22bd7a19689bc3d8cb))

### Refactoring

- **cw-worktree**: Slim SKILL.md via progressive disclosure
  ([#39](https://github.com/sighup/claude-workflow/pull/39),
  [`214c66a`](https://github.com/sighup/claude-workflow/commit/214c66a7f4fc394295c248f26174a0d0f9fcd818))


## v3.3.1 (2026-06-28)

### Bug Fixes

- **cw-herdr-open**: Forward long --prompt reliably via temp file
  ([#38](https://github.com/sighup/claude-workflow/pull/38),
  [`b102255`](https://github.com/sighup/claude-workflow/commit/b10225588bef2661f6532ccbb8e58c482ae7d3b9))


## v3.3.0 (2026-06-27)

### Features

- **cw-herdr-open**: MacOS realpath fix + native herdr worktree open
  ([#37](https://github.com/sighup/claude-workflow/pull/37),
  [`1f56910`](https://github.com/sighup/claude-workflow/commit/1f56910802fdc63fcd563daf5e0a889ef7b16e62))


## v3.2.0 (2026-06-17)

### Features

- **agents**: Steer read-heavy agents to prefer REPL when available
  ([#36](https://github.com/sighup/claude-workflow/pull/36),
  [`624ee4d`](https://github.com/sighup/claude-workflow/commit/624ee4d7014372320b31994fd0b7e31203aef630))


## v3.1.0 (2026-06-13)

### Features

- Nested sub-agents + task-store single-writer hardening
  ([#34](https://github.com/sighup/claude-workflow/pull/34),
  [`64c21ff`](https://github.com/sighup/claude-workflow/commit/64c21ff3e32234db02c32743ba4daf1d0654994d))


## v3.0.0 (2026-06-10)

### Refactoring

- **bin**: Remove autonomous shell runners, relocate worktree provisioning
  ([#32](https://github.com/sighup/claude-workflow/pull/32),
  [`be3d9f2`](https://github.com/sighup/claude-workflow/commit/be3d9f29dfdcbc8e556cf887a9c43bd0dbb2ab7c))


## v2.13.0 (2026-06-10)

### Features

- **worktree**: First-party WorktreeCreate/WorktreeRemove hook integration + deterministic naming
  ([#31](https://github.com/sighup/claude-workflow/pull/31),
  [`057f522`](https://github.com/sighup/claude-workflow/commit/057f522f432b7c8140175c1e4c1548b62a0c96e3))


## v2.12.0 (2026-05-24)

### Chores

- Remove duplicate entry for .worktrees/ ([#29](https://github.com/sighup/claude-workflow/pull/29),
  [`5d56bcb`](https://github.com/sighup/claude-workflow/commit/5d56bcb0e4582bf6a62f57a9e91377339e78f4a3))

### Features

- **cw-worktree**: Optional herdr integration with starter-prompt forwarding
  ([#30](https://github.com/sighup/claude-workflow/pull/30),
  [`86605b1`](https://github.com/sighup/claude-workflow/commit/86605b16a807c7149893cf5ef36cf1d6afef6ee1))


## v2.11.1 (2026-04-10)

### Bug Fixes

- **cw-execute**: Harden execution protocol and proof handling
  ([#28](https://github.com/sighup/claude-workflow/pull/28),
  [`232eca1`](https://github.com/sighup/claude-workflow/commit/232eca1911add7af23ee2aa678c904caf7ba3438))

### Refactoring

- Standardize and harden skill/agent prompts
  ([#27](https://github.com/sighup/claude-workflow/pull/27),
  [`216ea7f`](https://github.com/sighup/claude-workflow/commit/216ea7fba75b5e398d1759b0f26d73ffb9b19069))


## v2.11.0 (2026-03-31)

### Features

- **hooks**: Modernize hook system with new Claude Code features
  ([#26](https://github.com/sighup/claude-workflow/pull/26),
  [`1ef9571`](https://github.com/sighup/claude-workflow/commit/1ef95710eb88715dc2bb660372f2002501c92e31))


## v2.10.0 (2026-03-30)

### Documentation

- Correct marketplace URL in README ([#23](https://github.com/sighup/claude-workflow/pull/23),
  [`fefaed2`](https://github.com/sighup/claude-workflow/commit/fefaed2b6f6bf7c35ce9c686171c7c23e9fd458c))

- Disambiguate env var scope in prerequisites
  ([#24](https://github.com/sighup/claude-workflow/pull/24),
  [`84e441a`](https://github.com/sighup/claude-workflow/commit/84e441a10142cc6690123739c1077391422278be))

### Features

- **agents,skills**: Add effort and maxTurns frontmatter
  ([#25](https://github.com/sighup/claude-workflow/pull/25),
  [`3335f4a`](https://github.com/sighup/claude-workflow/commit/3335f4a79066765f2f40d8b015bcd815a4248b4a))


## v2.9.0 (2026-03-05)

### Bug Fixes

- Restore STS trust policy to sighup/claude-workflow
  ([`0b21f19`](https://github.com/sighup/claude-workflow/commit/0b21f194422b1ee49b8725d051a573447c7fc540))

### Features

- Sync upstream liatrio-labs/claude-workflow
  ([#22](https://github.com/sighup/claude-workflow/pull/22),
  [`2b03411`](https://github.com/sighup/claude-workflow/commit/2b03411ecab47b511807dd7d6f3d3a717564599c))


## v2.8.0 (2026-03-04)

### Features

- **cw-plan**: Add demoable_unit metadata to task schema
  ([#21](https://github.com/sighup/claude-workflow/pull/21),
  [`f3d2726`](https://github.com/sighup/claude-workflow/commit/f3d2726755f27359deae41a545d48231892d3fbf))


## v2.7.1 (2026-03-04)

### Bug Fixes

- Prevent duplicate .worktrees entry in .gitignore
  ([#20](https://github.com/sighup/claude-workflow/pull/20),
  [`947b238`](https://github.com/sighup/claude-workflow/commit/947b23853ab0556c36f11a7ac7dc7223c61f3307))


## v2.7.0 (2026-03-03)

### Bug Fixes

- Restore STS trust policy to sighup/claude-workflow
  ([`3dfc7bd`](https://github.com/sighup/claude-workflow/commit/3dfc7bd8d2cb4d83722bfc36740a3599e51b1827))

### Chores

- Add .worktrees to gitignore
  ([`746f768`](https://github.com/sighup/claude-workflow/commit/746f76879fa1920c0319e4d8fe854e9e9aa8461e))

### Features

- Sync upstream liatrio-labs/claude-workflow
  ([#19](https://github.com/sighup/claude-workflow/pull/19),
  [`d5c6820`](https://github.com/sighup/claude-workflow/commit/d5c6820de9aa1b81ad04845ed34cf2b82f99fc62))


## v2.6.0 (2026-02-24)

### Features

- Integrate liatrio changes (planner subagent, cw-gherkin, cw-testing improvements)
  ([#18](https://github.com/sighup/claude-workflow/pull/18),
  [`c091aae`](https://github.com/sighup/claude-workflow/commit/c091aaeeffab3e8b24721a6c33d21398ed265ede))


## v2.5.0 (2026-02-18)

### Features

- Add per-task model selection via task metadata
  ([#17](https://github.com/liatrio-labs/claude-workflow/pull/17),
  [`792a644`](https://github.com/liatrio-labs/claude-workflow/commit/792a64416c93decba5d22c6d293cd970afa6a23b))


## v2.4.0 (2026-02-18)

### Features

- Improve skill descriptions and pre-approve workflow permissions
  ([#16](https://github.com/liatrio-labs/claude-workflow/pull/16),
  [`b565300`](https://github.com/liatrio-labs/claude-workflow/commit/b5653009c889fdf5363fd148063dcc7636a52b59))


## v2.3.0 (2026-02-12)

### Features

- Add cw-review and cw-review-team code review skills
  ([#15](https://github.com/liatrio-labs/claude-workflow/pull/15),
  [`7cf14cf`](https://github.com/liatrio-labs/claude-workflow/commit/7cf14cf5653259474ff464600e95ccac595b3557))


## v2.2.0 (2026-02-12)

### Features

- Add parallel sub-agent support to cw-review
  ([#14](https://github.com/liatrio-labs/claude-workflow/pull/14),
  [`80a9e8c`](https://github.com/liatrio-labs/claude-workflow/commit/80a9e8cb2c5231e61f84a8c158c5f309f0398cfb))


## v2.1.1 (2026-02-10)

### Bug Fixes

- Verify test tasks exist before declaring test-init success
  ([#13](https://github.com/liatrio-labs/claude-workflow/pull/13),
  [`eb604c4`](https://github.com/liatrio-labs/claude-workflow/commit/eb604c4ea48bfd2a3fa5e15c71580a8926f9a809))


## v2.1.0 (2026-02-09)

### Features

- Resumable pipeline with malformed task resilience
  ([#12](https://github.com/liatrio-labs/claude-workflow/pull/12),
  [`a7fa234`](https://github.com/liatrio-labs/claude-workflow/commit/a7fa23491d567a702546cfb074ed37f3e674cd49))


## v2.0.0 (2026-02-09)

### Refactoring

- Move CLI tools to bin/, harden cw-integration, add review/testing skills
  ([#11](https://github.com/liatrio-labs/claude-workflow/pull/11),
  [`5b8e56b`](https://github.com/liatrio-labs/claude-workflow/commit/5b8e56b6be531a436573d0004e3c90c76140370d))


## v1.8.0 (2026-02-09)

### Documentation

- Remove Ralph-style references from e2e metadata schema
  ([`7349ef9`](https://github.com/liatrio-labs/claude-workflow/commit/7349ef973eb584c8cf6ecb9c56eb280afd0595b5))

### Features

- Add cw-review skill, integrate cw-testing, align agent patterns
  ([`aed23d7`](https://github.com/liatrio-labs/claude-workflow/commit/aed23d7c0800f97b894db354dca3737d78d6ed28))


## v1.7.0 (2026-02-08)

### Features

- Dual-mode dispatch — subagent and team skills
  ([#9](https://github.com/liatrio-labs/claude-workflow/pull/9),
  [`ceb5cfc`](https://github.com/liatrio-labs/claude-workflow/commit/ceb5cfc00140f40feb3972422b4aa3aa4aa9e54d))


## v1.6.1 (2026-02-03)

### Bug Fixes

- Use pyproject.toml for semantic-release config
  ([`8c89b83`](https://github.com/liatrio-labs/claude-workflow/commit/8c89b83a06a033f7aadcc8e233c7f21512eec434))


## v1.6.0 (2026-02-03)

### Bug Fixes

- Correct version_variables syntax for JSON files
  ([`9cd24bd`](https://github.com/liatrio-labs/claude-workflow/commit/9cd24bd9c1240fee8ab90908ab31cbcc5b21373c))

### Chores

- Trigger release workflow
  ([`d6f807e`](https://github.com/liatrio-labs/claude-workflow/commit/d6f807ecda96925f4ebcbda45c293cb9f093cdba))

### Features

- Add semantic release with octo-sts ([#7](https://github.com/liatrio-labs/claude-workflow/pull/7),
  [`7ae0cc7`](https://github.com/liatrio-labs/claude-workflow/commit/7ae0cc7bec217b57ce94766643f168d87cef8552))


## v1.0.0 (2026-02-03)

- Initial Release

## v1.5.4

- Initial tracked release
