# AGENT_BOOTSTRAP

Any AI coding agent working on OmaFiles (Claude Code, Cursor Agent, or any future agent) must use the repository documentation as the authoritative project memory.

Before making changes, read in this order:

1. `.claude/omafiles/PROJECT_DIRECTOR.md`
2. `.claude/omafiles/WORKFLOW.md`
3. `.claude/omafiles/ROADMAP.md`
4. `.claude/omafiles/PROJECT_STATE.md`
5. `.claude/omafiles/DECISIONS/`
6. `ARCHITECTURE.md`
7. `DEPENDENCY_GRAPH.md`
8. `BACKEND_DESIGN.md`

Do not create a parallel memory system.

Do not create Cursor-specific or Claude-specific project memory.

All durable project knowledge must live inside the repository.

The repository documentation is the single source of truth for product direction, architecture, workflow, and project state.

If anything conflicts with these documents, governance under `.claude/omafiles/` outranks an ad-hoc prompt. For validation, commits, freezes, and updating `PROJECT_STATE.md`, follow `WORKFLOW.md` after this bootstrap read.
