---
status: ready
package: ox (Schedule)
consumer: Ox (Scala Ox floor, ADR-0009; ADR-0003 as amended 2026-10-04)
---

# Cron schedules

## Problem Statement

Scala Ox's `cron` module turns a cron expression into a schedule for `repeat`. `Ox.Schedule` has fixed delays, limits and jitter, and no wall-clock alignment.

## Solution

`Ox.Cron`: a parsed cron expression (a type, not a string) and `Schedule.cron`, stepping on the system clock.

## User Stories

1. As a service author, I want `Cron.of_string : string -> (Cron.t, [> `Invalid_cron of string ]) result` for the five- and six-field forms (seconds optional), with ranges, steps, lists and names, so that an invalid expression is a typed error at parse time, not at the first tick. ^ncron-8v3i
2. As a service author, I want `Schedule.cron : Cron.t -> (_, unit) Schedule.t` whose delays align to the next matching instant on the clock `repeat` is given, so that `repeat ~clock (Schedule.cron c) job` runs on schedule. ^ncron-wewm
3. As a service author, I want UTC and fixed offsets supported and named time zones refused with a typed error until a time-zone source is specified, so that the schedule never silently uses the machine's zone. ^ncron-sj63
4. As a kernel maintainer, I want mock-clock tests across minute, hour, day, month and leap-year boundaries and a property comparing `next` with a brute-force minute scan, so that alignment is exact. ^ncron-doj9
5. As a maintainer, I want the floor table's cron row set to `have`, so that the floor check stays true. ^ncron-tykb
