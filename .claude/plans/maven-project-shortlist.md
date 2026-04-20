# Maven Project Shortlist

## Goal

Pick the next Maven-based AOT/cache experiment to replace Jetty.

## Candidates

1. `commons-compress`
   Best current option. Small real dependency tree, easy workload.
2. `httpcomponents-client`
   Good fallback. Clear runtime deps, easy local HTTP workload.
3. `commons-configuration`
   Acceptable middle ground. More interesting than CSV/IO, still manageable.
4. `commons-csv` or `commons-io`
   Safe/simple baseline options if we want the easiest path first.

## Avoid For Now

- `jetty`
  Deferred. `module-info.java` / `--patch-module` interferes with AOT dump.
- `gson`, `jackson-*`
  Lower priority because JPMS/module descriptors may introduce similar friction.

## Todo

- Decide one candidate.
- Create a dedicated experiment plan for that project.
- Prefer `commons-compress` unless we want an even simpler baseline.
