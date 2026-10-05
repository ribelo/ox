(* ^safe-y047 ^nlintcov-q6n2: exercise discovery, not a copied string parser. *)
let run ~caps =
  match Array.to_list Sys.argv with
  | [ _; "generated"; root ] -> (
      match Artifact.generated_sources ~caps ~root with
      | Error message -> failwith message
      | Ok entries ->
          if
            not
              (List.exists
                 (fun (entry : Artifact.generated) ->
                   entry.path = Filename.concat root "_build/default/generated.ml"
                   && Option.is_some entry.producer)
                 entries)
          then failwith "recursive inventory lost the declared generated test module")
  | _ :: expected :: sources when sources <> [] ->
      List.iter
        (fun source ->
          match (expected, Artifact.membership ~caps source) with
          | "built", Artifact.Built Artifact.Library | "unknown", Artifact.Unknown -> ()
          | _ -> failwith ("unexpected inventory membership: " ^ source))
        sources
  | _ -> failwith "expected generated ROOT or built/unknown SOURCE..."

let () = run ~caps:(Ox_caps_door.powerbox ())
