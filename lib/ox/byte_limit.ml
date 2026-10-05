type t = int

let of_int value = if value < 0 then Error `Invalid else Ok value
let to_int value = value
let zero = 0
let one = 1
