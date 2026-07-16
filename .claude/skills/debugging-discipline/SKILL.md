---
name: debugging-discipline
description: Disciplined approach for diagnosing failures, especially environment- or deployment-specific ones (green in one env, red in another). Use before reaching for deep infrastructure theories.
---

# Debugging discipline

When diagnosing a failure — especially an environment- or deployment-specific one —
work through these before reaching for deep infrastructure theories:

- **Config-parity first.** When the _same build/image_ is healthy in one
  environment and broken in another, diff the per-environment **configuration** (env
  vars, secrets, config maps) **before** investigating code, mounts, or timing. A
  green staging + red prod on an identical build is a config delta until proven
  otherwise.
- **Diagnose the real process, not a convenience shell.** Env-dependent behavior
  (`$HOME`, `expanduser`, `PATH`) can differ between an interactive shell
  (`kubectl exec`, SSH) and the actual service process, because the runtime may
  inject env from the user's passwd entry for exec sessions only. Read the real
  process's environment (e.g. `/proc/1/environ`), not an exec shell's `echo $HOME`.
- **Reproduce with the app's real inputs.** When something fails in-app but "works"
  in a manual test, make the manual test use the **same resolved config/arguments**
  the app uses — not hardcoded stand-ins. A hardcoded value that passes proves
  nothing about the config-derived path.
- **Pick the single decisive check.** When each diagnostic round-trips through a
  human or slow tooling, choose the one test that discriminates between the leading
  hypotheses in a single step instead of iterating one theory at a time.
- **Drop disproven theories and their artifacts immediately.** When a hypothesis is
  refuted, discard any half-built fix or branch for it — do not push a dead branch
  or apply a known no-op "just in case".
