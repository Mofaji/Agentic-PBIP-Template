# Contributing

Thank you for contributing!

- Use `.github/` for workflow and community guidance.
- Add new skills under `.claude/skills/<skill-name>/SKILL.md`. The folder name and the frontmatter `name:` must match, and the `description:` must say *when* to use the skill - that description is the only signal the agent routes on.
- Write a spec under `specs/` before building a new dashboard or page; see `specs/README.md`.
- Add validation tests under `tests/`.
- Keep files small, focused, and easy to follow.
