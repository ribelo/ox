# ox-resource-without-release-path

Authenticated raw acquisitions need handle-specific local cleanup. Use
Switch.on_release, Resource.use_in_scope, use_closeable_in_scope or
Fun.protect ~finally. Equivalent resolved local exception guards are accepted.
An unrelated finalizer does not cover another handle; tuple endpoints are distinct.

This is a structural policy, not a claim that every finding is a reproduced leak.
Imported ownership helpers are outside its local evidence boundary.
[Specification](<../issues/ox-safety-gate/21-resource-release.md>).
