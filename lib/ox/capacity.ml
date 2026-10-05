type t = int

let of_int value = if value < 1 then Error `Invalid else Ok value
let to_int value = value
