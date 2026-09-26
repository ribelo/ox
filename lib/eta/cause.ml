type 'e t =
  | Fail of 'e
  | Die of exn * Printexc.raw_backtrace
  | Interrupt of Interrupt_id.t option
  | Finalizer of 'e t
  | Suppressed of { primary : 'e t; finalizer : 'e t }
  | Concurrent of 'e t list

let rec pp pp_error fmt = function
  | Fail e -> Format.fprintf fmt "Fail(%a)" pp_error e
  | Die (ex, bt) -> Format.fprintf fmt "Die(%s; %s)" (Printexc.to_string ex) (Printexc.raw_backtrace_to_string bt)
  | Interrupt None -> Format.pp_print_string fmt "Interrupt(external)"
  | Interrupt (Some id) -> Format.fprintf fmt "Interrupt(%a)" Interrupt_id.pp id
  | Finalizer cause -> Format.fprintf fmt "Finalizer(%a)" (pp pp_error) cause
  | Suppressed { primary; finalizer } ->
      Format.fprintf fmt "Suppressed(primary=%a; finalizer=%a)" (pp pp_error) primary (pp pp_error) finalizer
  | Concurrent causes ->
      Format.fprintf fmt "Concurrent[%a]" (Format.pp_print_list ~pp_sep:(fun fmt () -> Format.pp_print_string fmt "; ") (pp pp_error)) causes

let rec pp_compact pp_error fmt = function
  | Fail e -> Format.fprintf fmt "Fail(%a)" pp_error e
  | Die (ex, _) -> Format.fprintf fmt "Die(%s)" (Printexc.to_string ex)
  | Interrupt None -> Format.pp_print_string fmt "Interrupt(external)"
  | Interrupt (Some id) -> Format.fprintf fmt "Interrupt(%a)" Interrupt_id.pp id
  | Finalizer c -> Format.fprintf fmt "Finalizer(%a)" (pp_compact pp_error) c
  | Suppressed { primary; finalizer } ->
      Format.fprintf fmt "Suppressed(%a; %a)" (pp_compact pp_error) primary (pp_compact pp_error) finalizer
  | Concurrent cs ->
      Format.fprintf fmt "Concurrent[%a]" (Format.pp_print_list ~pp_sep:(fun fmt () -> Format.pp_print_string fmt "; ") (pp_compact pp_error)) cs

let rec is_interrupt_only = function
  | Interrupt _ -> true
  | Concurrent cs -> cs <> [] && List.for_all is_interrupt_only cs
  | _ -> false
