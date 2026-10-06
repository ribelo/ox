(* ^nlintd-k036 *)
module Alias = Concurrency_clean_export_dependency.Helper

module Included = struct
  include Alias
end

include Included

(* ^nlintd-k036: the raise clause names the known sibling, not its opaque leaf. *)
let delegated_raise sw = Docs_dependency.unknown_raise sw
