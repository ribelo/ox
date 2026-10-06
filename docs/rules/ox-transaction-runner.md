# ox-transaction-runner

**Active:** ordinary repository gates prevent originating-pool reborrows; the architect’s prevention decision does not require complete consumer admission for this rule. ^safe-ldtb ^safe-j6t8 ^safe-r1xw

Report authentic originating-pool operations inside its transaction callback; use the supplied transaction runner. Local aliases/helpers preserve runner identity. The callback runner and proven independent pools remain legal; unresolved transmitted/captured runners are named undecided, not a general lifetime certificate. Compiler UIDs and imported interface evidence authenticate the APIs.

One [clean pair](<../../test/lint/clean/transaction_runner.ml>), [violating pair](<../../test/lint/violating/transaction_runner.ml>) and [MI-first corpus](<../../test/lint/safety_transaction_runner/corpus.ml>) compare full sorted observations without deduplication and accept external artifact/source pairs. A real size-one SQLite pool deadlocks when its transaction callback re-borrows the originating pool; a bounded subprocess requires timeout124. The callback runner commits one row and preserves it when the next insertion returns an error and rolls back.
