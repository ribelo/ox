(* ^nlintd-k036 *)
module Alias = Concurrency_violating_export_dependency.Helper
module Included = struct
  include Alias
end
include Included

(* ^nlintd-k036: a total known callee cannot justify a conditional raise. *)
let false_delegated_raise sw = Docs_dependency.noop sw

(* ^nlintd-k036: unrelated opacity must not qualify that total callee. *)
let unrelated_raise sw =
  Docs_dependency.noop sw;
  ignore (Format.asprintf "%d" 1)