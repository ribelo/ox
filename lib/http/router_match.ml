(* Copyright (c) 2026 Ox contributors. SPDX-License-Identifier: MIT *)

(* Copied from v1:lib/router/match.ml (story ^hserv-e3q9); module paths adapted only. *)

module Params = Router_params

type 'a t = { value : 'a; params : Params.t }
