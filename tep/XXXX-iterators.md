---
status: proposed
title: Iterators
creation-date: '2026-03-09'
last-updated: '2026-03-09'
authors:
- '@waveywaves'
see-also:
- TEP-0090
- TEP-0056
- TEP-0033
- TEP-0145
---

# TEP-XXXX: Iterators

<!-- toc -->
- [Summary](#summary)
- [Motivation](#motivation)
  - [Community Demand](#community-demand)
  - [Goals](#goals)
  - [Non-Goals](#non-goals)
  - [Requirements](#requirements)
  - [Use Cases](#use-cases)
  - [Related Tekton Projects](#related-tekton-projects)
  - [Related Work](#related-work)
- [Proposal](#proposal)
  - [API Change](#api-change)
  - [Context Variables](#context-variables)
  - [Convergence Detection](#convergence-detection)
  - [Execution Semantics](#execution-semantics)
  - [Interaction with Existing Features](#interaction-with-existing-features)
- [Design Details](#design-details)
  - [Iterator State in PipelineRun Status](#iterator-state-in-pipelinerun-status)
  - [Status Size Management](#status-size-management)
  - [TaskRun Naming](#taskrun-naming)
  - [Result Passing Between Iterations](#result-passing-between-iterations)
  - [Result Forwarding to Downstream Tasks](#result-forwarding-to-downstream-tasks)
  - [CEL Expression Evaluation](#cel-expression-evaluation)
  - [Retries and Iterator Interaction](#retries-and-iterator-interaction)
  - [Timeout Semantics](#timeout-semantics)
  - [Finally Task Behavior](#finally-task-behavior)
  - [Cancellation Behavior](#cancellation-behavior)
  - [DAG Scheduling](#dag-scheduling)
  - [Reconciler Lifecycle](#reconciler-lifecycle)
  - [Validation Rules](#validation-rules)
  - [CRD Schema](#crd-schema)
- [Design Evaluation](#design-evaluation)
  - [API Conventions](#api-conventions)
  - [Reusability](#reusability)
  - [Simplicity](#simplicity)
  - [Flexibility](#flexibility)
  - [Conformance](#conformance)
  - [Performance](#performance)
  - [Security](#security)
  - [Provenance and SLSA](#provenance-and-slsa)
  - [Risks and Mitigations](#risks-and-mitigations)
  - [Drawbacks](#drawbacks)
- [Alternatives](#alternatives)
  - [Triggers-based PipelineRun Chaining](#triggers-based-pipelinerun-chaining)
  - [CustomTask Controller](#customtask-controller)
  - [Recursive Pipelines-in-Pipelines](#recursive-pipelines-in-pipelines)
  - [Retry with Expression](#retry-with-expression)
  - [Top-level Iterator Construct](#top-level-iterator-construct)
- [Implementation Plan](#implementation-plan)
  - [Milestones](#milestones)
  - [Test Plan](#test-plan)
  - [Upgrade and Migration Strategy](#upgrade-and-migration-strategy)
  - [Implementation Pull Requests](#implementation-pull-requests)
- [References](#references)
<!-- /toc -->

## Summary

This TEP proposes adding an `iterator` field to `PipelineTask` that enables sequential,
bounded iteration within a single PipelineRun. An Iterator runs a Task repeatedly, passing
results from one iteration to the next, and stops when either a CEL convergence expression
evaluates to true or the maximum iteration count is reached.

This fills the gap between Tekton's existing parallel fan-out primitive (Matrix) and the
sequential, feedback-driven iteration that workloads like progressive deployment,
incremental migration, batch processing, convergence-based testing, and ML training
require.

```yaml
tasks:
  - name: deploy-and-validate
    iterator:
      maxIterations: "$(params.max-stages)"
      timeout: "2h"
      until: "'$(iterator.previousResult.rollout-complete)' == 'true'"
    taskRef:
      name: progressive-rollout
    params:
      - name: stage
        value: "$(iterator.index)"
      - name: previous-health
        value: "$(iterator.previousResult.health-score)"
```

## Motivation

Tekton provides powerful primitives for expressing CI/CD workflows as directed acyclic
graphs of Tasks. Matrix enables parallel fan-out across parameter combinations, When
enables conditional execution, and Finally enables cleanup tasks. However, Tekton has
no primitive for **sequential iteration with feedback** -- running a Task repeatedly
where each iteration's output informs the next iteration's input.

This gap has been raised repeatedly by the community:

- The [Task Loops experimental project][task-loops] in `tektoncd/experimental`
  validated demand for looping in Tekton. When Matrix (TEP-0090) was designed,
  it absorbed the parallel fan-out use case but explicitly left the sequential
  iteration case unaddressed.
- [tektoncd/pipeline#2050][issue-2050] and related discussions requested native
  iteration support beyond what Matrix provides.
- Multiple users have built workarounds using Triggers-based PipelineRun chaining
  or shell loops inside Steps, indicating the gap is actively felt.

The gap affects multiple workload categories:

**Progressive deployment.** Multi-stage rollouts (staging -> canary -> production)
where each stage depends on the previous stage's validation result. Today, this
requires either a monolithic Step or Triggers-based chaining.

**Incremental database migration.** Applying schema migrations one-at-a-time,
validating each before proceeding to the next. Each migration depends on the
previous migration's success.

**Batch data processing.** Processing a large dataset in chunks where each chunk
depends on the cursor/offset from the previous chunk.

**Convergence-based testing.** Flaky test detection, performance benchmarking, and
chaos engineering that require running tests repeatedly until a statistical
threshold is met.

**Polling and approval gates.** Waiting for an external system to reach a desired
state by polling until a condition is satisfied.

**Machine learning training.** ML training runs N epochs, checks a loss metric,
and continues if convergence is not met. Each iteration depends on the previous
checkpoint.

Matrix solves the **parallel fan-out** case where iterations are independent.
Iterators solve the **sequential feedback** case where each iteration depends on
the previous one. They are complementary primitives.

### Community Demand

The need for sequential iteration has been raised in multiple contexts:

- **Task Loops Experimental Project** (`tektoncd/experimental/task-loops`): This
  project implemented loop functionality as a CustomTask controller, validating
  demand. When Matrix (TEP-0090) was designed, it explicitly referenced this
  project (see TEP-0090 lines 1420-1427) but only absorbed the parallel fan-out
  case. The sequential iteration case was left as future work.
- **GitHub Issues**: [tektoncd/pipeline#2050][issue-2050] and related issues
  requesting iteration/looping support.
- **Real-world validation**: A [neuroevolution training system][saiyan-trainer]
  used a prototype implementation of this feature across 80 loop iterations
  (20 batches x 4 parallel PipelineRuns) with 100% reliability over a 6-hour
  training run.

### Goals

1. Enable bounded, sequential iteration within a PipelineTask where each iteration
   can pass results to the next iteration.
2. Support convergence detection via CEL expressions that evaluate against previous
   iteration results, allowing early termination when a goal is met.
3. Provide mandatory safety bounds (`maxIterations`, `timeout`) to prevent unbounded
   resource consumption.
4. Store iteration state in PipelineRun status for observability and debuggability.
5. Integrate with Tekton's existing DAG scheduling so downstream tasks wait for all
   iterations to complete.
6. Follow the same feature gate pattern as Matrix (alpha -> beta -> stable).

### Non-Goals

1. Parallel iteration. Matrix already handles parallel fan-out. Composing Iterator
   with Matrix (fan-out within each iteration) is a future goal, not part of this TEP.
2. Infinite or unbounded iteration. `maxIterations` is required and must resolve to
   a positive integer.
3. Mutable shared state between iterations beyond result passing. Each iteration is a
   separate TaskRun; state sharing happens through explicit result parameters, not
   shared memory or volumes. (Workspaces provide shared storage at the PVC level, but
   iteration-to-iteration data flow uses Results.)
4. Nested iterators. An iterated Task cannot itself contain an iterator. This may be
   addressed in a future TEP.

### Requirements

1. The Iterator MUST be bounded: `maxIterations` is required and must resolve to a
   positive integer. A cluster-level upper bound MUST be configurable via ConfigMap.
2. The Iterator MUST support an optional `until` CEL expression for convergence
   detection.
3. The Iterator MUST pass the current iteration index and previous iteration results
   to each iteration via context variables.
4. The Iterator MUST NOT require the underlying Task to be iterator-aware. Any existing
   Task or Task from the Catalog should work inside an Iterator without modification.
5. Iteration MUST be sequential: iteration N+1 starts only after iteration N completes
   successfully.
6. If any iteration fails (after exhausting retries), the Iterator MUST stop and report
   failure.
7. The Iterator state (current iteration, results per iteration, termination reason)
   MUST be visible in PipelineRun status.
8. Downstream tasks (via `runAfter`) MUST wait for all iterations to complete before
   executing.
9. Iterator and Matrix MUST be mutually exclusive on the same PipelineTask.
10. The Iterator MUST be gated behind a feature flag, starting at alpha stability.
11. CEL expression errors MUST fail the iterator by default, not silently continue.

### Use Cases

#### UC-1: Progressive Multi-Stage Deployment

A platform engineer performs a progressive rollout: deploy to staging, validate health,
deploy to canary (10%), validate, then deploy to production. Each stage depends on the
previous stage's health check.

```yaml
tasks:
  - name: progressive-deploy
    iterator:
      maxIterations: "$(params.num-stages)"
      until: "'$(iterator.previousResult.rollout-complete)' == 'true'"
    taskRef:
      name: deploy-and-validate
    params:
      - name: stage-index
        value: "$(iterator.index)"
      - name: previous-health
        value: "$(iterator.previousResult.health-score)"
      - name: environment
        value: "$(params.target-env)"
  - name: notify-complete
    runAfter: ["progressive-deploy"]
    taskRef:
      name: send-notification
```

#### UC-2: Incremental Database Migration

A DevOps engineer applies database migrations one-at-a-time, validating each before
proceeding. The migration stops early if a validation check fails.

```yaml
tasks:
  - name: apply-migration
    iterator:
      maxIterations: "$(params.migration-count)"
      timeout: "30m"
      until: "'$(iterator.previousResult.all-applied)' == 'true'"
    taskRef:
      name: run-migration-step
    params:
      - name: migration-index
        value: "$(iterator.index)"
      - name: previous-checksum
        value: "$(iterator.previousResult.schema-checksum)"
```

#### UC-3: Batch Data Processing with Cursor Pagination

A data engineer processes a large database table in chunks of 1000 rows. Each iteration
returns a cursor for the next batch. Processing stops when the cursor is empty.

```yaml
tasks:
  - name: process-batch
    iterator:
      maxIterations: "100"
      until: "'$(iterator.previousResult.next-cursor)' == ''"
    taskRef:
      name: process-data-chunk
    params:
      - name: cursor
        value: "$(iterator.previousResult.next-cursor)"
      - name: batch-size
        value: "1000"
```

#### UC-4: Convergence-Based Performance Testing

A performance engineer runs load tests repeatedly until the p99 latency stabilizes
within a 5% variance window across 3 consecutive runs.

```yaml
tasks:
  - name: load-test
    iterator:
      maxIterations: "20"
      until: "'$(iterator.previousResult.stable)' == 'true'"
    taskRef:
      name: run-load-test
    params:
      - name: target-url
        value: "$(params.service-url)"
      - name: iteration
        value: "$(iterator.index)"
```

#### UC-5: Polling an External System

A deployment pipeline waits for a canary rollout to reach 100% by polling the
deployment status every iteration.

```yaml
tasks:
  - name: wait-for-rollout
    iterator:
      maxIterations: "30"
      timeout: "15m"
      until: "'$(iterator.previousResult.rollout-complete)' == 'true'"
    taskRef:
      name: check-rollout-status
    params:
      - name: deployment
        value: "$(params.deployment-name)"
```

#### UC-6: ML Training with Convergence Detection

A machine learning engineer trains a model iteratively, passing the best metric
between iterations. Training stops early if a fitness threshold is exceeded.

```yaml
tasks:
  - name: train-batch
    iterator:
      maxIterations: "50"
      timeout: "6h"
      until: "double('$(iterator.previousResult.best-fitness)') >= 5000.0"
    taskRef:
      name: run-training-batch
    params:
      - name: batch-number
        value: "$(iterator.index)"
    workspaces:
      - name: training-data
        workspace: shared-pvc
```

### Related Tekton Projects

**Task Loops Experimental Project** (`tektoncd/experimental/task-loops`): This project
implemented loop functionality as a CustomTask controller. It validated demand for
iteration in Tekton pipelines. When Matrix (TEP-0090) was designed, it referenced this
project and absorbed the parallel fan-out use case. The sequential iteration use case
was explicitly left for future work. This TEP completes that picture.

The experimental Task Loops controller demonstrated both the demand and the limitations
of the CustomTask approach:
- It required deploying a separate controller
- Per-iteration status was not visible in the PipelineRun status
- Integration with the DAG scheduler was limited
- Result propagation to downstream tasks was not seamless

These limitations inform why this TEP proposes a first-class `iterator` field rather
than formalizing the CustomTask approach (see [Alternatives](#customtask-controller)).

### Related Work

| System | Iteration Primitive | Convergence Support | State Passing |
|--------|-------------------|-------------------|---------------|
| **Argo Workflows** | `withItems`/`withParam` (parallel fan-out); recursive templates; sequential `steps` within DAG templates | Recursive `when` guards; `retryStrategy.expression` (CEL-like expression evaluated against step outputs to conditionally retry) | Step outputs as JSON; template parameters for recursion |
| **GitHub Actions** | `strategy.matrix` (parallel only) | `fail-fast` (failure only) | `needs` + `outputs` (no iteration state) |
| **Kubernetes Jobs** | Indexed Jobs (`completionMode: Indexed`) | None (run to `completions`) | None (external storage) |
| **Kubeflow Pipelines** | `dsl.ParallelFor` (v2, parallel); `@dsl.graph_component` recursion (v1, **deprecated**) | v1 recursion with `dsl.Condition` (**deprecated, no v2 replacement**) | `dsl.Collected` for fan-in; function parameters for recursion |
| **Azure Logic Apps** | `Until` action (native convergence loop); `For Each` | Native: expression + count limit + timeout limit | First-class workflow variables (mutable across iterations) |
| **Temporal** | `continueAsNew` (history-bounded iteration) | Return from workflow function | Workflow state as function argument |

Key observations:

- **No CI/CD system has a first-class sequential iteration primitive with convergence
  detection.** Argo comes closest with `retryStrategy.expression` for conditional
  re-execution, but that is retry semantics (re-run on failure), not iteration
  semantics (advance on success). Argo's sequential `steps` do not support dynamic
  iteration counts.
- **Azure Logic Apps' `Until` action** is the closest analog to the proposed Iterator:
  expression-based termination, mandatory count/timeout limits, sequential execution.
- **Kubeflow's deprecation of v1 recursion** without a v2 replacement demonstrates
  that the ML/data community needs this primitive and no one has solved it well.
- **Temporal's `continueAsNew`** teaches that unbounded iteration creates unbounded
  state/history; the Iterator must manage status size.

## Proposal

### API Change

Add an `iterator` field to `PipelineTask`:

```go
type PipelineTask struct {
    // ... existing fields ...

    // Iterator enables sequential, bounded iteration of this task.
    // Each iteration runs the task once, passing results from the previous
    // iteration to the next. The iterator stops when the Until condition
    // evaluates to true or MaxIterations is reached.
    //
    // Iterator and Matrix are mutually exclusive.
    // +optional
    Iterator *Iterator `json:"iterator,omitempty"`
}
```

The `Iterator` type:

```go
// Iterator defines sequential iteration configuration for a PipelineTask.
type Iterator struct {
    // MaxIterations is the maximum number of times the task will be executed.
    // Required. Must resolve to a positive integer. Supports $(params.*)
    // substitution for runtime configurability. Capped by the cluster-level
    // max-iterator-iterations setting in config-defaults ConfigMap.
    MaxIterations string `json:"maxIterations"`

    // Timeout is the maximum total wall-clock duration for all iterations
    // combined. If exceeded, the iterator stops with IteratorTimedOut.
    // Uses the same duration format as PipelineTask timeout (e.g., "1h30m").
    // If not specified, the pipeline-level timeout applies.
    // +optional
    Timeout *metav1.Duration `json:"timeout,omitempty"`

    // Until is an optional CEL expression that is evaluated after each
    // iteration completes. If it evaluates to true, the iterator stops
    // (convergence). The expression can reference $(iterator.index)
    // and $(iterator.previousResult.<name>) which are substituted before
    // CEL evaluation. CEL errors fail the iterator by default.
    // +optional
    Until string `json:"until,omitempty"`
}
```

**Key design decisions:**

- **`maxIterations` is a `string`, not `int`.** This allows `$(params.*)` substitution
  so the same Pipeline can be reused across environments (e.g., 5 iterations in dev,
  200 in prod). The value is validated at runtime to be a positive integer. A
  cluster-level hard cap (`max-iterator-iterations` in `config-defaults` ConfigMap,
  default: 100) prevents abuse regardless of the parameter value. This follows the
  Reusability principle: "At run time, users should be able to control execution as
  needed without modifying Tasks and Pipelines."

- **No `iterationParams` field.** Iterator context variables (`$(iterator.index)`,
  `$(iterator.previousResult.<name>)`) are available directly in regular `params`
  values. This is consistent with how Matrix works -- Matrix does not introduce
  `matrixParams`, it uses the existing `params` field with `$(matrix.*)` substitution.
  Eliminating a separate parameter list reduces API surface and avoids confusion about
  parameter precedence.

- **`timeout` bounds total iterator duration.** The PipelineTask-level `timeout`
  applies per-iteration. The `iterator.timeout` bounds the total wall-clock time
  across all iterations. This prevents the scenario where `timeout: 10m` with
  `maxIterations: 50` runs for 500 minutes.

Add `IteratorStates` to `PipelineRunStatusFields`:

```go
type PipelineRunStatusFields struct {
    // ... existing fields ...

    // IteratorStates tracks the state of each iterated PipelineTask.
    // +optional
    IteratorStates []IteratorState `json:"iteratorStates,omitempty"`
}
```

### Context Variables

Two new context variable prefixes are introduced:

| Variable | Type | Description |
|----------|------|-------------|
| `$(iterator.index)` | string (integer) | 0-indexed iteration number |
| `$(iterator.previousResult.<name>)` | string | Named result from the most recently completed iteration. Resolves to empty string on iteration 0. |

These variables are available in:
- `params[].value` on the PipelineTask (when the task has an `iterator`)
- `iterator.until`

They follow the same `$(scope.field)` pattern as existing context variables
(`$(params.name)`, `$(tasks.name.results.field)`, `$(context.pipelineRun.name)`).

### Convergence Detection

The `until` field accepts a CEL expression. Before evaluation, `$(iterator.*)`
placeholders are textually substituted with their runtime values. The resulting
string is compiled and evaluated as CEL. If the expression returns `true`, the
iterator terminates with reason `Converged`.

Examples:

```yaml
# Stop when a result equals a specific value
until: "'$(iterator.previousResult.converged)' == 'true'"

# Stop when a numeric threshold is exceeded
until: "double('$(iterator.previousResult.best-fitness)') >= 5000.0"

# Stop when a result is empty (cursor exhausted)
until: "'$(iterator.previousResult.next-cursor)' == ''"

# Stop after a minimum number of iterations with a condition
until: "int('$(iterator.index)') >= 5 && '$(iterator.previousResult.stable)' == 'true'"
```

**CEL error handling:** If CEL compilation or evaluation fails at runtime, the
iterator **fails immediately** with `TerminationReason: CelEvaluationFailed` and
a descriptive error message in the IteratorState. This prevents silent iteration
continuation due to typos in result names or expression syntax errors.

Using CEL follows Tekton's design principle: "Avoid implementing our own expression
syntax; when required prefer existing languages (e.g., CEL)." CEL is already used
in When expressions (alpha feature, [TEP-0145][tep-0145]).

### Execution Semantics

1. **Initialization:** The reconciler resolves `maxIterations` (applying param
   substitution if needed), validates it as a positive integer, and creates a
   TaskRun for iteration 0 with `$(iterator.*)` variables substituted in params.
2. **Advancement:** When iteration N completes successfully:
   a. Record results in `IteratorState.Iterations[N]`.
   b. If `until` is specified, evaluate it with results from iteration N.
      If CEL evaluation fails, mark iterator failed with `CelEvaluationFailed`.
   c. If `until` returns `true`, mark iterator complete with `Converged`.
   d. If `N+1 >= maxIterations`, mark iterator complete with `MaxIterationsReached`.
   e. If `iterator.timeout` is exceeded, mark iterator complete with `TimedOut`.
   f. Otherwise, create TaskRun for iteration N+1 with updated context variables.
3. **Failure:** If any iteration's TaskRun fails (after exhausting retries), the
   iterator stops with `IterationFailed`. The PipelineTask is marked as failed.
4. **Cancellation:** If the PipelineRun is cancelled, no new iterations are created.
   Running iteration TaskRuns are cancelled per normal Tekton cancellation semantics.
   The iterator is marked with `TerminationReason: Cancelled`.

### Interaction with Existing Features

| Feature | Interaction |
|---------|-------------|
| **Matrix** | Mutually exclusive. `apis.ErrMultipleOneOf("iterator", "matrix")` at validation. Future TEP may enable composition. |
| **When** | When expressions are evaluated once before the iterator starts. If the When condition is false, the entire iterator is skipped. |
| **Retries** | Per-iteration. Retry count resets for each iteration. See [Retries and Iterator Interaction](#retries-and-iterator-interaction). |
| **Timeout** | PipelineTask `timeout` applies per-iteration. `iterator.timeout` bounds total duration. See [Timeout Semantics](#timeout-semantics). |
| **Finally** | Finally tasks run after all iterators complete (or fail). See [Finally Task Behavior](#finally-task-behavior). |
| **Workspaces** | Bound once, shared across all iterations. Enables checkpoint-based state sharing via PVC. |
| **Results** | `$(tasks.<iterator-task>.results.<name>)` returns the last *successfully completed* iteration's result. See [Result Forwarding](#result-forwarding-to-downstream-tasks). |
| **Pipelines-in-Pipelines** | An iterated PipelineTask can reference a child Pipeline via `pipelineRef`/`pipelineSpec`, enabling iteration over an entire Pipeline. |

## Design Details

### Iterator State in PipelineRun Status

```go
// IteratorState tracks the execution state of an iterated PipelineTask.
type IteratorState struct {
    PipelineTaskName  string                    `json:"pipelineTaskName"`
    CurrentIteration  int                       `json:"currentIteration"`
    MaxIterations     int                       `json:"maxIterations"`
    Converged         bool                      `json:"converged,omitempty"`
    TerminationReason IteratorTerminationReason  `json:"terminationReason,omitempty"`
    Iterations        []IterationState          `json:"iterations,omitempty"`
}

type IterationState struct {
    Iteration   int               `json:"iteration"`
    TaskRunName string            `json:"taskRunName,omitempty"`
    Status      IterationStatus   `json:"status,omitempty"`
    Results     []TaskRunResult   `json:"results,omitempty"`
}

type IteratorTerminationReason string

const (
    IteratorTerminationReasonConverged            IteratorTerminationReason = "Converged"
    IteratorTerminationReasonMaxIterationsReached  IteratorTerminationReason = "MaxIterationsReached"
    IteratorTerminationReasonIterationFailed       IteratorTerminationReason = "IterationFailed"
    IteratorTerminationReasonTimedOut              IteratorTerminationReason = "TimedOut"
    IteratorTerminationReasonCelEvaluationFailed   IteratorTerminationReason = "CelEvaluationFailed"
    IteratorTerminationReasonCancelled             IteratorTerminationReason = "Cancelled"
)

type IterationStatus string

const (
    IterationStatusRunning   IterationStatus = "Running"
    IterationStatusSucceeded IterationStatus = "Succeeded"
    IterationStatusFailed    IterationStatus = "Failed"
)
```

### Status Size Management

The `Iterations` slice grows linearly with iteration count. To prevent PipelineRun
status from approaching the etcd 1.5MB object size limit:

- **Alpha:** Full iteration history retained, bounded by `maxIterations` (cluster
  default cap: 100). At 100 iterations with 3 results each (~100 bytes per result),
  this adds ~30KB -- well within limits.
- **Beta:** Introduce configurable result retention. Only the last N iterations'
  results are kept in status (default N=20). Older iteration results are available
  by reading the corresponding TaskRun directly. The `Iteration`, `TaskRunName`, and
  `Status` fields are always retained for all iterations (these are small).
- The cluster-level `max-iterator-iterations` cap in `config-defaults` provides a
  hard upper bound on status growth.

### TaskRun Naming

Iterator TaskRuns follow the pattern:

```
<pipelinerun-name>-<pipelinetask-name>-iter-<N>
```

Where `<N>` is the 0-indexed iteration number. If the combined name exceeds the
Kubernetes 63-character limit, `kmeta.ChildName` hashes the base name and the
`-iter-<N>` suffix is re-appended to ensure it is always present.

### Result Passing Between Iterations

Results flow between iterations through the `$(iterator.previousResult.<name>)`
context variable:

1. When iteration N completes, its TaskRun results are recorded in
   `IteratorState.Iterations[N].Results`.
2. When creating the TaskRun for iteration N+1, `params` values containing
   `$(iterator.previousResult.<name>)` are substituted with the corresponding
   result value from iteration N.
3. On iteration 0, `$(iterator.previousResult.<name>)` resolves to an empty
   string `""`, since there is no previous iteration.

### Result Forwarding to Downstream Tasks

When a downstream task references `$(tasks.<iterator-task>.results.<name>)`, it
receives the result from the **last successfully completed iteration**.

Specifically:
- If the iterator terminates with `Converged` or `MaxIterationsReached`, the
  results from the final iteration are used.
- If the iterator terminates with `IterationFailed`, the results from the last
  *successful* iteration (N-1) are used. If iteration 0 failed, no results are
  available and the downstream reference fails resolution.
- If the iterator terminates with `Cancelled` or `TimedOut`, the same logic
  applies: results from the last successful iteration.

**Alpha status:** Result forwarding to downstream tasks is implemented in the
prototype. The standard Tekton result resolution is modified to look up the
last successful iteration's TaskRun results for iterated PipelineTasks.

### CEL Expression Evaluation

The `until` expression is evaluated using the following process:

1. **Variable substitution:** All `$(iterator.*)` placeholders in the expression
   are replaced with their string values using `strings.ReplaceAll`.
2. **CEL compilation:** The substituted string is compiled using `cel.NewEnv()`
   with no custom declarations (all values are inlined as string literals).
3. **CEL evaluation:** The compiled program is evaluated. The result must be a
   `bool`.
4. **Error handling:** If CEL compilation or evaluation fails, the iterator
   **fails immediately** with `TerminationReason: CelEvaluationFailed`. The
   error message is recorded in the IteratorState for debugging.

**Note on textual substitution:** If a task result value contains characters that
break CEL syntax (e.g., single quotes), the CEL expression will fail to compile.
Users should ensure result values are safe for CEL string literal embedding. A
future improvement could pass results as CEL variables in the environment rather
than inlining them as string literals, avoiding this fragility.

**Admission-time validation:** When a Pipeline is created or updated, the `until`
expression is validated by compiling it as CEL. Expressions containing `$(`
placeholders are skipped since they are not valid CEL until runtime substitution.

### Retries and Iterator Interaction

When `retries` is set on an iterated PipelineTask:

- **Scope:** Retries apply per-iteration. If iteration N's TaskRun fails, it is
  retried up to `retries` times before the iterator considers the iteration failed.
- **Count reset:** The retry count resets to 0 for each new iteration. Iteration
  N+1 gets a fresh retry budget regardless of how many retries iteration N used.
- **Result source:** If iteration N fails and a retry succeeds, the `until`
  expression evaluates against the *successful retry's* results.
- **TaskRun naming:** Retries use Tekton's native retry mechanism (same TaskRun
  with incremented retry count in status), not additional `-retry-M` TaskRuns.
- **Resource bound:** With `retries: R` and `maxIterations: M`, the maximum
  number of pod creations is `M * (R + 1)`. This is accounted for in the
  cluster-level resource exhaustion calculations.

### Timeout Semantics

Two timeout levels apply to iterators:

1. **Per-iteration timeout (`PipelineTask.timeout`):** Applies to each individual
   iteration's TaskRun. If iteration N exceeds this timeout, the TaskRun fails
   and the iterator considers it a failed iteration (subject to retries).

2. **Total iterator timeout (`iterator.timeout`):** Bounds the total wall-clock
   time from the first iteration's start to the current time. Checked before
   creating each new iteration. If exceeded, the iterator terminates with
   `TerminationReason: TimedOut`. This prevents `timeout: 10m` with
   `maxIterations: 50` from running for 500 minutes.

3. **Pipeline-level timeout (`spec.timeouts.pipeline`):** Applies to the entire
   Pipeline, including all iterators. This is the outermost bound.

If `iterator.timeout` is not specified, only the pipeline-level timeout applies
as the total bound.

### Finally Task Behavior

Finally tasks interact with iterators as follows:

| Iterator termination | Finally tasks run? | Result availability |
|---------------------|--------------------|---------------------|
| `Converged` | Yes | Last iteration's results |
| `MaxIterationsReached` | Yes | Last iteration's results |
| `IterationFailed` | Yes | Last *successful* iteration's results (if any) |
| `TimedOut` | Yes | Last successful iteration's results (if any) |
| `CelEvaluationFailed` | Yes | Last successful iteration's results (if any) |
| `Cancelled` | Yes (per normal cancellation semantics) | Last successful iteration's results (if any) |

### Cancellation Behavior

When a PipelineRun is cancelled (gracefully or forcefully):

1. No new iteration TaskRuns are created.
2. Any running iteration TaskRun is cancelled per normal Tekton semantics.
3. The IteratorState is updated with `TerminationReason: Cancelled`.
4. The iterator is marked complete.
5. Finally tasks execute per normal cancellation behavior.

### DAG Scheduling

The iterator integrates with Tekton's DAG scheduler:

1. **`isSuccessful()` override:** For iterated PipelineTasks, returns `true` only
   when the iterator is complete AND the termination reason is `Converged` or
   `MaxIterationsReached` (i.e., no failure).
2. **`isFailure()` override:** Returns `true` when the iterator is complete AND
   the termination reason is `IterationFailed`, `CelEvaluationFailed`, or `TimedOut`.
3. **`IteratorComplete` flag:** A runtime-only boolean on `ResolvedPipelineTask`
   (not serialized) that the reconciler sets after checking iterator state.

### Reconciler Lifecycle

```
reconcile()
  -> for each resolved PipelineTask:
       if IsIterated():
         -> handleIteratedTask()
              -> GetOrCreateIteratorState()
              -> if complete: return
              -> check iterator.timeout: if exceeded, mark TimedOut, return
              -> find latest iteration TaskRun
              -> if running: return (wait)
              -> if succeeded:
                   -> record results
                   -> evaluate Until expression
                   -> if CEL error: mark CelEvaluationFailed, return
                   -> if converged: mark Converged, return
                   -> if maxIterations reached: mark MaxIterationsReached, return
                   -> create next iteration TaskRun
              -> if failed (after retries exhausted):
                   -> mark IterationFailed, return
              -> if no TaskRun: create iteration 0 TaskRun
```

**State recovery:** If `IteratorState` is missing (e.g., CRD schema stripping),
the reconciler recovers by scanning TaskRuns matching `<run>-<task>-iter-<N>`.

### Validation Rules

| Rule | Error | When |
|------|-------|------|
| `maxIterations` must resolve to positive integer | `invalid value: must be a positive integer` | Admission (literal) or runtime (param) |
| `maxIterations` must not exceed cluster cap | `exceeds max-iterator-iterations limit` | Runtime |
| `until` must be valid CEL (when no `$(` placeholders) | `invalid CEL expression` | Admission |
| `iterator` and `matrix` are mutually exclusive | `expected exactly one, got both` | Admission |
| Feature gate `enable-api-fields: alpha` required | `iterator requires alpha API fields` | Admission |
| `$(iterator.*)` variables only valid in params of iterated tasks | `invalid variable reference` | Admission |
| `iterator.timeout` must be valid duration | `invalid duration format` | Admission |

### CRD Schema

```yaml
iterator:
  type: object
  properties:
    maxIterations:
      type: string
    timeout:
      type: string
    until:
      type: string
```

During alpha, `x-kubernetes-preserve-unknown-fields: true` on the status object
allows `iteratorStates` to be persisted without a full schema. A proper status
schema will be added when the feature graduates to beta.

## Design Evaluation

### API Conventions

- Optional pointer type (`*Iterator`) on `PipelineTask`, consistent with `*Matrix`
- Uses standard JSON tags with `omitempty`
- Uses existing Tekton types (`Params`, `TaskRunResult`)
- `maxIterations` as string follows the pattern of other parameterizable fields

### Reusability

**Tasks remain reusable.** The Iterator is configured at the PipelineTask level.
The underlying Task needs no modification. Any Catalog Task works inside an
Iterator without changes.

**Pipelines remain reusable.** `maxIterations` accepts `$(params.*)` substitution,
so the same Pipeline works across environments (dev: 5 iterations, prod: 200)
without modification. This follows the Reusability principle: "At run time, users
should be able to control execution as needed without modifying Tasks and Pipelines."

### Simplicity

**Is this feature absolutely necessary?** Yes. The alternatives are documented in
[Alternatives](#alternatives). The Task Loops experimental project validated
demand. The CustomTask approach was tried and found limiting (see
[Related Tekton Projects](#related-tekton-projects)). No combination of existing
features provides single-PipelineRun lineage with per-iteration observability,
convergence detection, and DAG scheduler integration.

**Consistency with existing features.** The Iterator mirrors Matrix:
- Both are optional fields on `PipelineTask`
- Both create multiple TaskRuns from a single PipelineTask
- Both store state in PipelineRun status
- Both are mutually exclusive with each other
- Both are gated behind feature flags

Matrix fans out in parallel; Iterator runs sequentially with feedback.

### Flexibility

**CEL for convergence.** Follows the principle "avoid implementing our own
expression syntax; prefer existing languages."

**Plugin mechanisms exhausted.** The Task Loops experimental project implemented
iteration as a CustomTask controller. It worked but had significant limitations:
per-iteration status not visible in PipelineRun, limited DAG scheduler integration,
separate controller deployment required. The Iterator requires reconciler-level
integration that plugins cannot provide, specifically:
- Overriding `isSuccessful()`/`isFailure()` on `ResolvedPipelineTask` to prevent
  downstream tasks from executing after a single iteration
- Participating in the PipelineRun's result resolution for `$(tasks.*.results.*)`
- Storing state in the PipelineRun status object (not a separate Custom resource)

These touch internal reconciler interfaces that the CustomTask contract does not
expose.

### Conformance

- Not required for conformance; optional and feature-gated
- No new Kubernetes concepts; uses existing TaskRun children and status patterns
- Platform-agnostic; works on any Kubernetes distribution

### Performance

- **Pod overhead:** Each iteration creates a TaskRun/pod. Users should batch work
  per iteration to amortize scheduling overhead.
- **Status size:** Bounded by `maxIterations` cap (default 100). ~30KB worst case.
  Beta adds result retention to further limit growth.
- **Reconciler load:** One reconciliation per iteration. Negligible for typical
  iteration counts (20-50).

### Security

**Denial-of-service via unbounded iteration.** Mitigated by required
`maxIterations` with cluster-level cap (`max-iterator-iterations` in
`config-defaults`, default: 100). Additionally, `iterator.timeout` provides a
wall-clock bound.

**CEL expression injection.** CEL runs in a sandboxed environment with no custom
functions or variables. All values are inlined as string literals. The attack
surface is limited to string comparison and type conversion.

**Resource consumption.** Total pod creations bounded by
`maxIterations * (retries + 1)`. Cluster administrators can further limit via
ResourceQuotas and LimitRanges.

### Provenance and SLSA

**Attestation:** Each iteration creates a standard TaskRun. Tekton Chains signs
each iteration's TaskRun independently, producing per-iteration attestations.
The PipelineRun-level attestation includes all iteration TaskRuns as children.

**Reproducibility:** An iterator that converged at iteration 7 can be reproduced
by setting `maxIterations: 8` (or examining the `IteratorState` to see the exact
convergence point). All iteration results are recorded in status.

**Provenance chain:** The `IteratorState` provides a complete audit trail:
which iterations ran, what results each produced, and why the iterator stopped.
This is richer provenance than a monolithic Step that hides iteration internals.

### Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| `maxIterations` set too high | Cluster-level cap via `max-iterator-iterations` in `config-defaults` (default: 100) |
| CEL expression errors | Fail immediately with `CelEvaluationFailed` and descriptive error message |
| Status field grows large | Bounded by `maxIterations` cap; beta adds result retention compaction |
| Feature interaction bugs | Comprehensive test matrix covering Iterator x {Matrix, When, Retries, Finally, Timeout, Cancel} |
| CRD schema changes | `preserve-unknown-fields` in alpha; proper schema in beta |
| Textual CEL substitution fragility | Document result value requirements; beta may switch to CEL variable binding |
| Unbounded wall-clock time | `iterator.timeout` field bounds total duration |

### Drawbacks

1. **Adds reconciler complexity.** ~300 lines of reconciler code, comparable to
   Matrix.
2. **Sequential execution is slow.** Pod scheduling adds 10-30 seconds per
   iteration. Users should batch work per iteration.
3. **String-typed numeric comparisons in CEL.** `$(iterator.previousResult.*)`
   values are strings; numeric comparisons need `double()` or `int()` casts.
4. **Textual CEL substitution.** Result values containing single quotes break
   CEL expressions. A future improvement could use CEL variable binding instead.

## Alternatives

### Triggers-based PipelineRun Chaining

**Approach:** Use a `finally` task to POST to an EventListener when convergence
is not met, triggering a new PipelineRun.

**Why rejected:**
- Each iteration is a separate PipelineRun, losing run lineage.
- HTTP call between iterations adds latency and failure modes.
- Requires deploying Tekton Triggers infrastructure.
- Manual PipelineRun cleanup required.
- State passing requires external storage.

### CustomTask Controller

**Approach:** Implement iteration as a CustomTask (CustomRun) with its own
controller, as the Task Loops experimental project demonstrated.

**What works:**
- CustomRun results ARE propagated to downstream tasks via
  `$(tasks.<name>.results.<field>)` (available since Tekton Pipelines v0.44+).
- CustomRun status is visible via `ChildReferences`.
- Deploying a separate controller is consistent with Tekton's plugin architecture.

**What does not work (and why a first-class field is needed):**
- **DAG scheduling integration:** The PipelineRun reconciler's `isSuccessful()`
  and `isFailure()` methods need to understand that a CustomRun representing an
  iterator is not "successful" after its first child TaskRun succeeds. The
  CustomTask controller cannot influence these internal scheduling decisions.
- **Per-iteration observability:** While CustomRun status can store structured
  data, the PipelineRun status does not surface per-iteration progress natively.
  Users must inspect the CustomRun separately.
- **Unified status:** PipelineRun status shows a single `ChildStatusReference`
  for the CustomRun, not individual entries per iteration. This limits dashboard
  and CLI tooling.
- **Operational overhead:** Users must deploy, maintain, and version a separate
  controller alongside the Tekton Pipelines controller.

The Task Loops experimental project validated that these limitations are
significant enough to warrant a first-class primitive.

### Recursive Pipelines-in-Pipelines

**Approach:** A Pipeline calls itself recursively with When guards for convergence.

**Why rejected:**
- Tekton does not support recursive Pipeline references.
- Recursion without depth limits risks unbounded resource consumption.
- Kubeflow deprecated recursive `@dsl.graph_component` for similar reasons.

### Retry with Expression

**Approach:** Repurpose `retries` with a CEL expression (similar to Argo's
`retryStrategy.expression`).

**Why rejected:**
- Retries are semantically different: re-run on failure vs. advance on success.
- Conflating retry and iteration breaks existing retry behavior.
- Argo ships `retryStrategy.expression` successfully, but it serves a different
  purpose (conditional retry, not sequential advancement with state passing).

### Top-level Iterator Construct

**Approach:** Add an `iterators` field to `PipelineSpec` alongside `tasks` and
`finally`.

**Why rejected:**
- Inconsistent with Matrix (which is on `PipelineTask`, not top-level).
- Requires a new scheduling mechanism instead of reusing the DAG scheduler.
- Users think of iteration as a task property ("run this task repeatedly").

## Implementation Plan

### Milestones

**Milestone 1: Alpha**
- `iterator` field on `PipelineTask` gated behind `enable-api-fields: alpha`
- Sequential iteration with `maxIterations` (string, supports param substitution)
- `iterator.timeout` for total duration bound
- `until` CEL expression with fail-on-error semantics
- `$(iterator.index)` and `$(iterator.previousResult.<name>)` in regular `params`
- `IteratorStates` in PipelineRun status with all termination reasons
- State recovery from TaskRuns when status is lost
- Mutual exclusivity with Matrix
- Result forwarding to downstream tasks (last successful iteration)
- Cluster-level `max-iterator-iterations` cap in `config-defaults`
- E2E tests, unit tests, documentation

**Milestone 2: Beta**
- Proper CRD schema (remove `preserve-unknown-fields` workaround)
- Status result retention (keep last N iterations' results, default N=20)
- Per-feature flag (`enable-iterators`) alongside global `enable-api-fields`
- Integration tests with When, Retries, Finally, Workspaces, Timeout, Cancel
- CEL variable binding (replace textual substitution to handle special chars)

**Milestone 3: Stable**
- Graduation to stable API
- Documentation in Tekton website and examples repository

### Test Plan

**Unit tests:**
- Iterator type validation (maxIterations bounds, CEL validity, mutual exclusivity)
- Context variable substitution (`$(iterator.index)`, `$(iterator.previousResult.*)`)
- CEL evaluation: success, failure, error handling
- DAG scheduling (isSuccessful/isFailure overrides)
- State recovery from TaskRuns
- `maxIterations` param substitution and cluster cap enforcement

**Integration tests:**
- Fixed iteration count (no `until`)
- `until` convergence (early termination)
- Failed iteration (`IterationFailed`)
- CEL evaluation error (`CelEvaluationFailed`)
- `iterator.timeout` exceeded (`TimedOut`)
- Retries per iteration (count reset, result source)
- `runAfter` downstream tasks with result forwarding
- When expression (skip entire iterator)
- Workspaces shared across iterations
- Pipeline-level timeout
- PipelineRun cancellation (`Cancelled`)
- Finally tasks after each termination reason
- `maxIterations` with `$(params.*)` substitution

**E2E tests:**
- Full iterator lifecycle on a Kind cluster
- State recovery after controller restart
- Concurrent PipelineRuns with iterators

### Upgrade and Migration Strategy

- **Alpha to beta:** No migration. Field name and semantics stable.
- **Beta to stable:** No migration. Feature graduates to always-available.
- **CRD:** `preserve-unknown-fields` workaround replaced by proper schema in beta.

### Implementation Pull Requests

A prototype implementation exists on the `feat/pipeline-iteration` branch of
[waveywaves/pipeline][prototype] (fork of `tektoncd/pipeline`). This prototype
validated the design across 80 iterations in a real-world ML training workload.

The prototype uses `loop` as the field name; renaming to `iterator` is a
mechanical change. The design is open to significant changes based on TEP review.

PRs will be opened against `tektoncd/pipeline` after TEP approval.

## References

- [TEP-0090: Matrix][tep-0090] -- Parallel fan-out primitive (complementary)
- [TEP-0056: Pipelines in Pipelines][tep-0056] -- Child Pipeline execution
- [TEP-0033: Tekton Feature Gates][tep-0033] -- Alpha/beta/stable gating
- [TEP-0138: Decouple API and Feature Versioning][tep-0138] -- Per-feature flags
- [TEP-0145: CEL in WhenExpressions][tep-0145] -- CEL precedent in Tekton
- [Tekton Design Principles][design-principles]
- [Task Loops Experimental Project][task-loops] -- Prior art validating iteration demand
- [CEL Specification][cel-spec] -- Expression language for `until`
- [Azure Logic Apps Until Action][azure-until] -- Closest industry analog
- [Argo Workflows Loops][argo-loops] -- Parallel fan-out and retryStrategy.expression
- [Kubeflow Pipelines Control Flow][kubeflow] -- Deprecated recursion, no v2 replacement
- [Saiyan Trainer][saiyan-trainer] -- Real-world validation (80 iterations, 100% reliability)

[tep-0090]: https://github.com/tektoncd/community/blob/main/teps/0090-matrix.md
[tep-0056]: https://github.com/tektoncd/community/blob/main/teps/0056-pipelines-in-pipelines.md
[tep-0033]: https://github.com/tektoncd/community/blob/main/teps/0033-tekton-feature-gates.md
[tep-0138]: https://github.com/tektoncd/community/blob/main/teps/0138-decouple-api-and-feature-versioning.md
[tep-0145]: https://github.com/tektoncd/community/blob/main/teps/0145-cel-in-whenexpression.md
[design-principles]: https://github.com/tektoncd/community/blob/main/design-principles.md
[task-loops]: https://github.com/tektoncd/experimental/tree/main/task-loops
[cel-spec]: https://github.com/google/cel-spec
[azure-until]: https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-control-flow-loops#until-loop
[argo-loops]: https://argo-workflows.readthedocs.io/en/latest/walk-through/loops/
[kubeflow]: https://www.kubeflow.org/docs/components/pipelines/
[saiyan-trainer]: https://github.com/waveywaves/saiyan-trainer
[prototype]: https://github.com/waveywaves/pipeline/tree/feat/pipeline-iteration
[issue-2050]: https://github.com/tektoncd/pipeline/issues/2050
