type error =
  | Sqlite of Sqlite.error
  | Pool_error of string
  | Invalid_query of string
  | Decode_error of { operation : string; message : string }

exception Error of error
