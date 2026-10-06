# ox-raw-sql-construction

**Dormant:** explicit audit only; dynamic SQL is not proof of injection. ^safe-8pmk ^safe-p1m1 ^safe-iq5u

Detect supported dynamic concatenation, join, formatting and Buffer construction reaching compiler-identified raw SQLite/Ox SQL sinks. Preserve bounded local source/sink helpers and aliases. Literal SQL with separately bound values is clean; opaque text and SQL grammar validation are outside this catalogue. Source/alias exhaustion at a known sink is named undecided.

Structural dynamic SQL can be a false positive: quoting an identifier does not make it a literal SQL value. Do not invent an identifier parser or suppress these migration findings; classify them explicitly and keep the rule dormant.

One [violating pair](<../../test/lint/violating/raw_sql_construction.ml>), [clean pair](<../../test/lint/clean/raw_sql_construction.ml>) and [MI-first consumer probe](<../../test/lint/safety_raw_sql/corpus.ml>) retain exact observations. Genuine in-memory Ox/Eio execution discloses two rows for injected unparameterized text; binding the identical input returns no rows. No fake sink or additional fixture matrix is shipped.
