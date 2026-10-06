(* ^safe-8pmk ^safe-iq5u: consumer data is concatenated, not parameter-bound. *)
module P = Ox_sql.Pool
let lookup runner input =
  let sql = "SELECT * FROM users WHERE name = '" ^ input ^ "'" in
  P.Raw.query runner sql []

(* ^safe-iq5u: a matching lexical module is not the trusted function. *)
let _counterfeit runner input =
  let module Ox_sql__Dsl = struct let quote_ident x = x end in
  let sql = "SELECT * FROM " ^ Ox_sql__Dsl.quote_ident input in
  P.Raw.query runner sql []

let _value_quote runner input =
  let sql = "SELECT * FROM '" ^ Ox_sql__Dsl.quote_ident input ^ "'" in
  P.Raw.query runner sql []

let _identifier_quote runner input =
  let sql = "SELECT * FROM \"" ^ Ox_sql__Dsl.quote_ident input ^ "\"" in
  P.Raw.query runner sql []

let _escaped_format runner input =
  let sql = Printf.sprintf "SELECT * FROM %S" (Ox_sql__Dsl.quote_ident input) in
  P.Raw.query runner sql []

let _comment runner input =
  let sql = "SELECT * FROM --" ^ Ox_sql__Dsl.quote_ident input in
  P.Raw.query runner sql []

let _format_boundary runner input =
  let prefix = Printf.sprintf "%s/" (Ox_sql__Dsl.quote_ident input) in
  let sql = prefix ^ "* WHERE hidden */" in
  P.Raw.query runner sql []

let _join_boundary runner input =
  let sql = String.concat "" [ "SELECT /"; "*"; Ox_sql__Dsl.quote_ident input ] in
  P.Raw.query runner sql []
