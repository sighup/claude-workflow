# CHANGELOG

<!-- version list -->

## v2.9.1 (2026-03-04)

### Bug Fixes

- **cw-worktree**: Prevent duplicate .worktrees entry in .gitignore
  ([#11](https://github.com/liatrio-labs/claude-workflow/pull/11),
  [`13e5d31`](https://github.com/liatrio-labs/claude-workflow/commit/13e5d3184906dfc9f56fb6b8e6fcdee6a79c9d1d))


## v2.9.0 (2026-03-02)

### Features

- Add LSP support across skills and agents
  ([#10](https://github.com/liatrio-labs/claude-workflow/pull/10),
  [`8a3ef6c`](https://github.com/liatrio-labs/claude-workflow/commit/8a3ef6cb69baaa9588c46ed879a50a0a50d8d098))

- Add LSP support to cw-execute, cw-review, cw-spec, and bug-fixer
  ([#10](https://github.com/liatrio-labs/claude-workflow/pull/10),
  [`8a3ef6c`](https://github.com/liatrio-labs/claude-workflow/commit/8a3ef6cb69baaa9588c46ed879a50a0a50d8d098))

- Save research report in directory so cw-spec can co-locate it with the spec
  ([#10](https://github.com/liatrio-labs/claude-workflow/pull/10),
  [`8a3ef6c`](https://github.com/liatrio-labs/claude-workflow/commit/8a3ef6cb69baaa9588c46ed879a50a0a50d8d098))


## v2.8.1 (2026-03-02)

### Bug Fixes

- **cw-research**: Add external context section to report template
  ([#9](https://github.com/liatrio-labs/claude-workflow/pull/9),
  [`86d4ab7`](https://github.com/liatrio-labs/claude-workflow/commit/86d4ab76f59b10cc1d9badf42c85a422b21ea966))


## v2.8.0 (2026-03-02)

### Bug Fixes

- **cw-research**: Add subagent_type: "Explore" to all Task() calls
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))

### Chores

- Remove spec artifacts from repository
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))

### Documentation

- Add cw-research to README workflow diagram and skills table
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))

- Add playwright-bdd as optional prerequisite for cw-testing
  ([#7](https://github.com/liatrio-labs/claude-workflow/pull/7),
  [`b22bb98`](https://github.com/liatrio-labs/claude-workflow/commit/b22bb9871ec427911b1de11cefa6623a1e72dce9))

### Features

- Add cw-research skill for codebase exploration
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))

- **cw-research**: Add interactive refinement with external context sources
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))

- **cw-research**: Add MANDATORY FIRST ACTION section for project detection
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))

- **cw-research**: Add meta-prompt generation, agent definition, and integration wiring
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))

- **cw-research**: Create core skill with auto-explore and basic report
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))

### Refactoring

- **cw-research**: Extract inline content to references/ directory
  ([#8](https://github.com/liatrio-labs/claude-workflow/pull/8),
  [`5c4f863`](https://github.com/liatrio-labs/claude-workflow/commit/5c4f8639fdabea5c62309ae5b572e14d9dd2d5d3))


## v2.7.1 (2026-02-24)

### Bug Fixes

- **cw-plan**: Remove null model option, always set explicit model
  ([#6](https://github.com/liatrio-labs/claude-workflow/pull/6),
  [`42c1b90`](https://github.com/liatrio-labs/claude-workflow/commit/42c1b90e35d7a87294ba82f8cae2dbf06e06cf59))


## v2.7.0 (2026-02-24)

### Features

- Add cw-gherkin skill and playwright-bdd test backend
  ([#5](https://github.com/liatrio-labs/claude-workflow/pull/5),
  [`3ffea70`](https://github.com/liatrio-labs/claude-workflow/commit/3ffea709e5d5505f9adc26547f47c473c4fa0786))


## v2.6.0 (2026-02-22)

### Bug Fixes

- Map standard complexity to sonnet instead of null
  ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))

- Present execution options in cw-spec after architect subagent completes
  ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))

- Restore version to 2.5.0 and remove spurious v1.0.0 changelog entry
  ([`0207405`](https://github.com/liatrio-labs/claude-workflow/commit/0207405739ba5e31d18b14c160b8eb6f24954143))

- Update remaining Architect reference to Planner in cw-spec
  ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))

### Chores

- New repo location
  ([`f4aed8f`](https://github.com/liatrio-labs/claude-workflow/commit/f4aed8f6a0bd42c9c566733fb10538a343618fe1))

- Update repo references from sighup to liatrio-labs
  ([`e4831d7`](https://github.com/liatrio-labs/claude-workflow/commit/e4831d739374bfe948771097eb914f99e6754c28))

### Documentation

- Add missing cw-review-team to skills table in README
  ([#2](https://github.com/liatrio-labs/claude-workflow/pull/2),
  [`5a1fdc8`](https://github.com/liatrio-labs/claude-workflow/commit/5a1fdc88d6a43a44ea8df11a902a8d9b667399e5))

- Clarify shell scripts are optional in README
  ([#1](https://github.com/liatrio-labs/claude-workflow/pull/1),
  [`0e39ce5`](https://github.com/liatrio-labs/claude-workflow/commit/0e39ce596d64437e4c70ab84848ab0cfeb894504))

- De-emphasize shell scripts and fix task metadata in README
  ([#1](https://github.com/liatrio-labs/claude-workflow/pull/1),
  [`0e39ce5`](https://github.com/liatrio-labs/claude-workflow/commit/0e39ce596d64437e4c70ab84848ab0cfeb894504))

### Features

- Add post-wave validation and improve execution option descriptions
  ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))

- Planner subagent with two-pass planning, context-aware recommendations, and execution routing
  ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))

- Set architect agent model to opus ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))

- Spawn architect subagent for /cw-plan from cw-spec
  ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))

- Two-pass architect spawning with context-aware sub-task recommendation
  ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))

### Refactoring

- Rename architect agent to planner ([#3](https://github.com/liatrio-labs/claude-workflow/pull/3),
  [`4baff14`](https://github.com/liatrio-labs/claude-workflow/commit/4baff14db00a077e743d3095d61a9f59d7475ece))


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
