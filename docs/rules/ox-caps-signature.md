# ox-caps-signature

^ncapslint-8jcy: dangerous operations require genuine abstract capability tokens supplied through an argument, directly or through a typed deps-record field. Nested closures may capture such argument authority. Module-level/global tokens or locally minted tokens are ambient authority, not arguments. A same-named method with an unrelated return type does not count.

The typed decider tracks parameter identities, record projections and direct aliases. It checks direct raw references and calls to resolved `Ox_caps.Cap_*` wrappers, not a whole-program call graph. Opaque re-exports and general higher-order propagation require additional reasoning. Build first; source-only runs name every module missing fresh typed evidence as undecided.

Compiled evidence: [violating](<../../test/caps/rules/violating/signature.ml>) and [clean](<../../test/caps/rules/clean/signature.ml>).
