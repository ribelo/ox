type kind = Header_invalid of { reason : string }
type t = { method_ : string; uri : string; kind : kind }

val make : method_:string -> uri:string -> kind -> t
