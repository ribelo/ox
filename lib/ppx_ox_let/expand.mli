(** [let%bind] and [let%map] for Ox results, whose continuations may be [local] and
    [yielding] (^nlet-q3z3).

    OxCaml elaborates binding operators ([let*]) with a [global unyielding] continuation,
    so a [local] scope handle or a [yielding] suspension token cannot be used after a
    [let*]. An ordinary application with [[@nontail]] keeps every mode refusal and lifts
    that restriction (ADR-0010). This rewriter writes that application for you:

    {[
      let%bind p = e in body   ~>  Ox.Result.bind e (fun p -> body) [@nontail]
      let%map p = e in body    ~>  Ox.Result.map e (fun p -> body) [@nontail]
      let%bind a = e1 and b = e2 in body
        ~>  Ox.Result.bind (Ox.Result.both e1 e2) (fun (a, b) -> body) [@nontail]
    ]}

    It is built on the compiler's own [compiler-libs] (ADR-0007), like
    [ppx_yojson_minimal]. A file that mentions neither [%bind] nor [%map] is returned
    byte-identical. Otherwise the output is the compiler's binary AST, so every location
    in it is the user's own and an error points at the program, not at the expansion
    (^nlet-axvf). A file that does not parse is returned unchanged for the compiler to
    report.

    Retire this package when binding operators accept mode-annotated continuations: the
    compiler's [parsing/parser.mly] carries "CR zqian: support mode annotation on letop",
    and oxcaml/oxcaml PR #6276 parses modes on binding operators without checking them yet
    (^nlet-z584). *)

val process : filename:string -> source:string -> (string, string) result
(** [process ~filename ~source] is the preprocessed file, or [Error] with a located
    message when a [%bind] or [%map] node has an unsupported shape. *)

val mapper : Ocaml_common.Ast_mapper.mapper
(** The rewriting mapper, exposed for the expansion tests. *)
