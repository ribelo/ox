---
status: ready
package: ox_kafka (new)
consumer: Ox (Scala Ox floor, ADR-0009; ADR-0003 as amended 2026-10-04)
---

# Kafka flows

## Problem Statement

Scala Ox's Kafka integration gives a consumer as a `Flow` source, a producer as a sink and a publishing stage, and offset commits as a stage after processing. Ox has no Kafka client. ADR-0005 allows unavoidable C bindings; the de-facto client is librdkafka.

## Solution

An ADR choosing the binding, then `ox_kafka` on `Flow` (row 76) in Scala Ox's shape.

## User Stories

1. As a maintainer, I want an ADR choosing between the `kafka` opam package (librdkafka bindings), our own minimal binding to librdkafka, and a pure-OCaml protocol client, with what each costs on 5.4.0+ox and under Eio (librdkafka's own threads and callbacks), so that the dependency is decided before code. ^nkafka-zlv0
2. As a service author, I want `Kafka.subscribe : ... -> (record, [> `Kafka of error ]) Flow.t`, so that consuming a topic is a Flow source. ^nkafka-q2lp
3. As a service author, I want `Kafka.publish` as a sink and `Kafka.map_publish` as a stage, so that producing is a Flow stage. ^nkafka-kxvk
4. As a service author, I want offsets committed by a stage after processing (`Kafka.commit_offsets`), at-least-once by construction, so that a crash never skips a record. ^nkafka-n8um
5. As a service author, I want the client's network and file access behind caps and Eio values (`docs/caps.md`), so that a Kafka service's signature says what it touches. ^nkafka-ekhe
6. As a kernel maintainer, I want tests against a real broker in a Nix-provided fixture behind an alias, and pure tests of the stages, so that the integration is proven without making `dune test` need a broker. ^nkafka-y8i4
7. As a maintainer, I want the floor table's Kafka row set to `have`, so that the floor check stays true. ^nkafka-4jyl
