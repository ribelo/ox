(* Copyright (c) 2026 Eta contributors. SPDX-License-Identifier: MIT *)

(* Copied from v1:lib/router/router.ml with v1:lib/router/eta_router.ml (story
   ^hserv-e3q9), flattened so that [Eta_http.Router] is the router itself: the
   top level is v1's [Eta_router.Router] and its [Error], [Params], [Match],
   [Escape] and [Route] are the submodules of the same name. Pure: no I/O, no
   clock, no [Effect.t]. *)

module Tree = Router_tree
module Escape = Router_escape
module Error = Router_error
module Params = Router_params
module Match = Router_match
module Route = Router_route

type 'a t = 'a Tree.t

let create () = Tree.empty ()
let insert router route value = Tree.insert router (Escape.of_string route) value

let[@inline always] at router path =
  match Tree.at_string router path with
  | Ok (value, params) -> Ok { Match.value; params }
  | Error e -> Error e

let find router path =
  match at router path with Ok { Match.value; _ } -> Some value | Error _ -> None

let remove router route = Tree.remove router (Escape.of_string route)
let merge ~into from = Tree.merge ~into from
let compress router = Tree.compress router
