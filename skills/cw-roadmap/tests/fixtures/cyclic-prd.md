---
type: prd
title: "Circular Pipeline Processor"
version: "0.1.0"
status: DRAFT
---

# Circular Pipeline Processor — PRD

**Product Requirements Document**

| Field | Value |
|-------|-------|
| Document Version | 0.1.0 |
| Status | DRAFT |
| Author | cw-frame |
| Date | 2026-04-23 |

> **Scope of this document:** Requirements and intent only. Implementation
> detail, architecture decisions, and acceptance criteria live in downstream
> specs and ADRs.

---

## 1. Executive Summary

### 1.1 Vision

A streaming data processor that ingests raw events, enriches them with
contextual metadata, and re-publishes enriched records back to the same
event bus for further consumption. The system creates a closed loop where
enriched events are themselves eligible for enrichment by downstream stages.

### 1.2 Problem

Batch-processing pipelines impose a high latency floor because every stage
must wait for its predecessor to complete before it can begin. Circular
enrichment pipelines allow a "best-available" model: each stage emits as
soon as its input is ready and can consume enriched records from later stages
via the shared bus, reducing end-to-end latency by up to 60%.

### 1.3 Target Users

| Persona | Primary Need |
|---------|--------------|
| Data Engineer | Low-latency enrichment without batch waits |
| Platform Operator | Observability into circular message flows |
| Product Analyst | Query over enriched events within seconds of ingestion |

---

## 2. Positioning

Circular Pipeline Processor competes with static DAG-based ETL platforms
(e.g. Airflow, Prefect) by allowing enrichment stages to form feedback
loops — a topology those platforms explicitly forbid. Unlike stream processors
that support recirculation (e.g. Apache Flink with iterative dataflows), this
system is purpose-built for the enrichment use case and exposes a simpler
configuration surface.

---

## 3. Core Workflow

1. Ingest — the Collector subscribes to the raw-events topic, validates schema,
   and writes validated records to the Enrichment Bus. Records that fail
   validation are dead-lettered.
2. Enrich — the Enricher reads from the Enrichment Bus, applies all registered
   enrichment plugins in topological order *where possible*, and emits enriched
   records back to the Enrichment Bus under a new schema version. Because
   plugins can themselves request outputs of other plugins, the Enricher must
   handle circular plugin dependencies at runtime by detecting fixed points.
3. Serve — the Query API tails the Enrichment Bus for records that have reached
   a "stable" enrichment state (no further enrichment expected in the next
   window) and indexes them for low-latency query.

---

## 4. Primary Capabilities

<!--
  NOTE FOR TEST HARNESS:
  These capabilities are deliberately authored so that a naive LLM decomposition
  would produce a cyclic slice graph:

  - Enrichment Plugin Registry requires Plugin Dependency Resolver (to register
    plugins with declared dependencies).
  - Plugin Dependency Resolver requires Enrichment Plugin Registry (to enumerate
    the registered plugins it must order).

  This mutual dependency is the "cyclic candidate" the fixture embeds. A
  DAG-aware decomposer must either merge these two capabilities into a single
  slice or reorder them by recognising that a stub registry is sufficient to
  bootstrap the resolver, which then validates full registrations.
-->

- **Schema Validator**: Validates raw events against the canonical Avro schema
  on ingest; dead-letters non-conforming records with a structured error
  envelope.
- **Enrichment Bus**: Managed Kafka topic pair (raw / enriched) with retention
  tuned for the enrichment window; provides exactly-once delivery semantics.
- **Enrichment Plugin Registry**: Stores plugin manifests (name, version, input
  schema, output schema, declared dependencies). Requires Plugin Dependency
  Resolver to validate manifests at registration time — a plugin whose
  dependency graph is itself cyclic must be rejected.
- **Plugin Dependency Resolver**: Builds a dependency graph across all
  registered plugins and emits a topological execution order. Requires
  Enrichment Plugin Registry to enumerate the full set of registered plugins
  before ordering. Detects fixed points (circular dependencies between plugins)
  and surfaces them as warnings rather than errors, enabling partial enrichment.
- **Fixed-Point Detector**: Identifies when a set of mutually-dependent plugins
  has converged to a stable output and signals the Serve stage that the record
  is ready for indexing.
- **Query API**: REST/GraphQL surface over indexed enriched records; supports
  time-range, schema-version, and plugin-contribution filters.
- **Observability Dashboard**: Real-time view of bus lag, enrichment latency
  per plugin, fixed-point convergence rate, and dead-letter queue depth.

---

## 5. Integrations

- **Apache Kafka 3.x**: Enrichment Bus transport layer.
- **Confluent Schema Registry**: Avro schema storage and compatibility checks.
- **Prometheus + Grafana**: Metrics export for the Observability Dashboard.
- **OpenTelemetry**: Distributed tracing across Collector → Enricher → Query API.

---

## 6. Domain Concepts

- **Enrichment Bus** — The Kafka topic pair (raw / enriched) through which all
  records flow. A record may traverse the bus multiple times as successive
  plugins enrich it.
- **Plugin** — A stateless enrichment function that consumes a record matching
  its declared input schema and emits a record matching its output schema. A
  plugin may declare dependencies on other plugins' output schemas.
- **Plugin Manifest** — The registration record for a plugin: name, version,
  input schema ref, output schema ref, and a list of plugin names whose output
  this plugin requires as input.
- **Fixed Point** — A stable state reached by a group of mutually-dependent
  plugins when no further enrichment changes the record within one bus pass.
- **Dead Letter** — A record that failed schema validation or exceeded the
  maximum enrichment retry count; stored in the dead-letter topic with a
  structured error envelope.
- **Enrichment Window** — The maximum elapsed time allowed for a record to
  reach a fixed point before it is marked stable-by-timeout and served as-is.
- **Topological Execution Order** — The sequence in which independent plugins
  are executed, derived from the Plugin Dependency Resolver's output. Mutually-
  dependent plugins are grouped into a fixed-point cluster and executed together.

---

## 7. Success Metrics

| Metric | Target |
|--------|--------|
| End-to-end enrichment latency (p99) | < 500 ms |
| Dead-letter rate | < 0.1% of ingested records |
| Fixed-point convergence rate | > 95% of records within enrichment window |
| Query API p99 latency | < 50 ms |
| Plugin registration success rate | > 99% (valid manifests accepted) |

---

## 8. Open Questions

1. Fixed-point timeout — should the enrichment window be a global constant or
   per-plugin-cluster? A per-cluster timeout enables finer control but
   complicates operator configuration.
2. Schema evolution — when a plugin's output schema changes, how are existing
   records on the bus handled? Re-enrichment from raw, or schema-compatible
   upgrade path?
3. Circular plugin dependency policy — the current design emits warnings for
   circular plugin dependencies and enables partial enrichment. Should the
   system instead reject circular plugin manifests at registration time, forcing
   decomposition into acyclic graphs?
4. Exactly-once delivery semantics at fixed-point — Kafka transactions cover
   the produce side; who coordinates the idempotency key across multiple passes
   for the same record?
5. Observability dashboard — ship as a bundled Grafana provisioning config or
   as a standalone frontend? The latter adds a second deployment surface.

_End of Document_
