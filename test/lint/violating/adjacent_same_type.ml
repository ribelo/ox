(* ^safe-pwlt ^safe-k6aa *)
let copy (src : string) (dst : string) = src ^ dst
let span (start : int) (stop : int) = stop - start
let bounds (low : float) (high : float) = high -. low
type path = string
let aliases (src : path) (dst : path) = src ^ dst
