# unbescape-workload

Synthetic workload that exercises the [unbescape](https://github.com/unbescape/unbescape) library for AOT cache generation.

The upstream unbescape repository has no test suite (`src/test` does not exist in the upstream repo). Because there are no upstream tests to run, a workload app is constructed here instead to drive class loading and warm the AOT cache.
