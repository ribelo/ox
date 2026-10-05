(* ^nparse-gb03 ^safe-6ukl: actual public constructors, not a test substitute. *)
let check_domain name of_int to_int minimum =
  List.iter
    (fun input ->
      match of_int input with
      | Error `Invalid ->
          if input >= minimum then failwith (name ^ ": rejected valid boundary")
      | Ok value ->
          if input < minimum then failwith (name ^ ": accepted invalid boundary");
          if to_int value <> input then failwith (name ^ ": integer changed"))
    [ min_int; -1; 0; 1; 16; 64; 1024; max_int ]

let run () =
  check_domain "Capacity" Ox.Capacity.of_int Ox.Capacity.to_int 1;
  check_domain "Concurrency" Ox.Concurrency.of_int Ox.Concurrency.to_int 1;
  check_domain "Byte_limit" Ox.Byte_limit.of_int Ox.Byte_limit.to_int 0;
  if Ox.Byte_limit.to_int Ox.Byte_limit.zero <> 0 then failwith "zero changed";
  if Ox.Byte_limit.to_int Ox.Byte_limit.one <> 1 then failwith "one changed"
