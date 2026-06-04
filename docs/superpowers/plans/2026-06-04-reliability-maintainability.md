# Reliability Maintainability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve the RabbitMQ experiment's correctness and maintainability without changing its core runtime behavior.

**Architecture:** Add small Erlang helper modules around reusable AMQP setup and publish confirm accounting. Keep publisher and consumer processes as the public runtime units, but move shared logic out of them. Make process counts and metric run labels configurable through `sys.config`.

**Tech Stack:** Erlang/OTP, erlang.mk, RabbitMQ `amqp_client`, ETS-backed in-process Prometheus formatting.

---

### Task 1: Publish Confirm Accounting

**Files:**
- Create: `src/mq/tuna_confirm.erl`
- Modify: `src/mq/tuna_publisher.erl`
- Modify: `src/tuna.app.src`

- [ ] Write EUnit tests in `tuna_confirm.erl` for single and multiple confirm settlement.
- [ ] Run `gmake eunit` or `make eunit` and verify the tests fail because `settle/3` is missing.
- [ ] Implement `tuna_confirm:settle/3`.
- [ ] Replace the private confirm settlement function in `tuna_publisher`.
- [ ] Run EUnit and compile.

### Task 2: Configurable Process Counts and Metric Run Labels

**Files:**
- Modify: `src/util/tuna_config.erl`
- Modify: `src/tuna_super_sup.erl`
- Modify: `src/metrics/tuna_metrics.erl`
- Modify: `config/sys.config`
- Modify: `README.md`

- [ ] Add EUnit tests for nested config lookup defaults and configured values.
- [ ] Run tests and verify they fail for the new exported functions.
- [ ] Add `publisher_count/0`, `classic_consumer_count/0`, `quorum_consumer_count/0`, and `metrics_run_id/0`.
- [ ] Use config counts in the supervisor instead of hardcoded macros.
- [ ] Make `tuna_metrics` append `{run_id, RunId}` to all metric label sets.
- [ ] Document the config knobs.

### Task 3: Shared AMQP Runtime Helper

**Files:**
- Create: `src/mq/tuna_amqp.erl`
- Modify: `src/mq/tuna_publisher.erl`
- Modify: `src/mq/tuna_classic_consumer.erl`
- Modify: `src/mq/tuna_quorum_consumer.erl`
- Modify: `src/tuna.app.src`

- [ ] Extract connection/channel opening with process monitors into `tuna_amqp:open/1`.
- [ ] Extract topic exchange declaration into `tuna_amqp:declare_exchange/1`.
- [ ] Extract consumer queue declaration, bind, qos, and consume setup into `tuna_amqp:consume/3`.
- [ ] Compile after each caller migration.

### Task 4: Connection Lifecycle Metrics

**Files:**
- Modify: `src/mq/tuna_publisher.erl`
- Modify: `src/mq/tuna_classic_consumer.erl`
- Modify: `src/mq/tuna_quorum_consumer.erl`
- Modify: `README.md`

- [ ] Increment `amqp_connect_total` after successful AMQP connection setup.
- [ ] Increment `amqp_down_total` when monitored connection or channel processes die.
- [ ] Keep existing crash/restart behavior unchanged.
- [ ] Compile and verify metrics formatting still works.
