# ox-cancel-mask-scope

**Dormant:** explicit audit only; no general termination certificate. ^safe-ctc4 ^safe-vj9b ^safe-tcqo

Detect genuine Eio await_cancel or run_server without a stop promise executing under cancellation protection. An inner finite timeout bounds the callback; a mask introduced inside an outer timeout defeats that timeout. Ready promises, finite cleanup and native settlement are not indefinite-work findings.

Track only bounded local aliases and executed helper/callback bodies. Direct primitive callbacks are executed; unused closures and partial applications are not. Dynamic protection/deadline/stop, recursive invocation horizons and fork switch context around known indefinite-wait candidates produce named undecided. Unrelated opaque cleanup is outside this catalogue, not unverified. Fork masks are not inferred from lexical ancestry. Boolean/option constructors retain canonical compiler type identity.

One [violating pair](<../../test/lint/violating/cancel_mask.ml>), [clean pair](<../../test/lint/clean/cancel_mask.ml>) and [MI-first consumer probe](<../../test/lint/safety_cancel_mask/corpus.ml>) preserve complete observation multisets. The bounded subprocess proves an outer timeout cannot settle a protected await_cancel. This is a concrete Ox/Eio cancellation failure, not proof that arbitrary cleanup terminates.
