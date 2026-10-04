(* lindec-ho00 lindec-4t98: the ppx driver output for [fixtures/wide_defaults.ml]
   must stay linear. Twenty defaulted fields of this shape are about 16 KB when each
   field is bound once; the bound is already below the old duplicated form at six
   defaulted fields. Each field is looked up once, and the unknown-key check and the
   record construction each occur once. *)

let bound = 32768

let read_file ~(caps : < Ox_caps.Cap.fs_read ; .. >) path =
  let channel = Ox_caps.Cap_stdlib.open_in_bin ~caps path in
  let length = in_channel_length channel in
  let text = really_input_string channel length in
  close_in channel;
  text

let count_substring needle haystack =
  let needle_len = String.length needle in
  let hay_len = String.length haystack in
  let count = ref 0 in
  let i = ref 0 in
  while !i + needle_len <= hay_len do
    if String.sub haystack !i needle_len = needle then incr count;
    incr i
  done;
  !count

let fail ~(caps : < Ox_caps.Cap.stderr ; Ox_caps.Cap.exit ; .. >) message =
  Ox_caps.Cap_stdlib.eprintf ~caps "size_bound: %s\n" message;
  Ox_caps.Cap_stdlib.exit ~caps 1

let main
    ~(caps :
       < Ox_caps.Cap.fs_read
       ; Ox_caps.Cap.stderr
       ; Ox_caps.Cap.stdout
       ; Ox_caps.Cap.exit
       ; .. >) () =
  match Sys.argv with
  | [| _; path |] ->
      let text = read_file ~caps path in
      let bytes = String.length text in
      if bytes >= bound then
        fail ~caps (Printf.sprintf "generated %d bytes, bound is %d" bytes bound);
      if bytes < 4000 then
        fail ~caps
          (Printf.sprintf "generated %d bytes; the driver did not expand the fixture"
             bytes);
      if count_substring "unknown field" text <> 1 then
        fail ~caps "unknown-field check was duplicated";
      if count_substring "Ok {" text <> 1 then
        fail ~caps "record construction was duplicated";
      if count_substring "yojson_of_wide" text <> 1 then
        fail ~caps "encoder was duplicated or missing";
      for i = 0 to 19 do
        let key = Printf.sprintf "f%02d" i in
        let lookups =
          count_substring (Printf.sprintf "Stdlib.List.assoc_opt %S" key) text
        in
        if lookups <> 1 then
          fail ~caps (Printf.sprintf "%s looked up %d times" key lookups);
        let bindings = count_substring (Printf.sprintf "_ppx_yojson_v_%s" key) text in
        if bindings <> 2 then fail ~caps (Printf.sprintf "%s bound %d times" key bindings)
      done;
      Ox_caps.Cap_stdlib.printf ~caps "wide_defaults.pp.ml %d bytes (bound %d)\n" bytes
        bound
  | _ ->
      Ox_caps.Cap_stdlib.eprintf ~caps "usage: size_bound <wide_defaults.pp.ml>\n";
      Ox_caps.Cap_stdlib.exit ~caps 2

let () =
  main
    ~caps:
      (Ox_test.powerbox ()
        :> < Ox_caps.Cap.fs_read
           ; Ox_caps.Cap.stderr
           ; Ox_caps.Cap.stdout
           ; Ox_caps.Cap.exit >)
    ()
