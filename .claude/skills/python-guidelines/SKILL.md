---
name: python-guidelines
description: Conventions for Python work — uv-managed environments, src/ layout, Ruff, pytest, typing. Use when writing or modifying Python in this or any synced repo.
---

# Python guidelines

Always use `uv` to manage Python environments and run Python commands. Check the
root folder for an existing environment before creating a new one. Follow "The
Hitchhiker's Guide to Python" conventions:

**Core principles**

- Prefer readability and explicitness over cleverness.
- Keep modules small and cohesive; avoid deep inheritance and over-abstraction.
- Prefer the standard library where practical; add dependencies only when justified.

**Project layout**

- Default to a `src/` layout (`src/<package_name>/...`) with clean import paths.
- Keep configuration, docs, and tooling files at the repo root.
- Put tests in `tests/`; keep them fast, deterministic, and isolated.
- Do not add tests for non-production surfaces — docs, infrastructure, scripts, dev
  tools, and repo-maintenance-only helpers. Check `AGENTS.md` for repo-specific
  exclusions.
- Organize by feature/domain rather than by "layers" unless the project benefits.

**Environment and dependencies**

- Assume an isolated virtual environment; use pinned, reproducible dependencies.
- Never modify global Python installations.

**Code style**

- Follow PEP 8. Prefer f-strings, pathlib, context managers, and type hints where
  they improve clarity. Write concise docstrings for public modules/classes/
  functions. Use exceptions intentionally; never blanket-catch without re-raising
  or logging.

**Tooling** (assume these unless the project says otherwise)

- Format/lint with Ruff (Black only if requested or already present).
- Type-check with mypy or pyright if the project types seriously.
- Test with pytest and fixtures; avoid network in unit tests.
- Log with the standard `logging` module; no print statements in library code.

**Async and concurrency**

- Use asyncio only for I/O concurrency; don't make everything async.
- Don't block the event loop; if forced to call blocking code from async, use
  `asyncio.to_thread()`.
