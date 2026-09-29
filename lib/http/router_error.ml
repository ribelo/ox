(* Copyright (c) 2026 Ox contributors. SPDX-License-Identifier: MIT *)

(* Copied from v1:lib/router/router_error.ml (story ^hserv-e3q9); module paths adapted only. *)

type insert = Conflict of string | Invalid_route of string
type match_ = Not_found
type merge = Conflicts of insert list
