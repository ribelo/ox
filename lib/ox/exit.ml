type ('a, 'e) t = Success of 'a | Failure of 'e Cause.t

let pp pp_value pp_error fmt = function
  | Success v -> Format.fprintf fmt "Success(%a)" pp_value v
  | Failure c -> Format.fprintf fmt "Failure(%a)" (Cause.pp pp_error) c

let is_interrupt_only = function
  | Failure c -> Cause.is_interrupt_only c
  | Success _ -> false

let to_result = function
  | Success v -> Ok (Ok v)
  | Failure (Cause.Fail e) -> Ok (Error e)
  | Failure c -> Error c

let process_code = function
  | Success _ -> 0
  | Failure c when Cause.is_interrupt_only c -> 130
  | Failure _ -> 1
