(* ^safe-y047 ^nlintcov-q6n2: exercise discovery, not a copied string parser. *)
let run ~caps =
  match Array.to_list Sys.argv with
  | [ _; "checked"; annotation; source ] ->
      let artifact = Artifact.read ~caps annotation in
      Artifact.check ~caps ~source artifact;
      Artifact.setup ~caps artifact
  | [ _; "generated"; root ] | [ _; "generated"; root; _ ] -> (
      let scope = if Array.length Sys.argv = 4 then Sys.argv.(3) else "" in
      match
        Artifact.generated_sources ~caps ~root
          ~sources:
            (Filename.concat (Filename.concat root scope) "dune"
            :: (if scope = "" then [] else [ Filename.concat root "fixtures/dune" ]))
      with
      | Error message -> failwith message
      | Ok entries ->
          if
            not
              (List.exists
                 (fun (entry : Artifact.generated) ->
                   entry.path
                   = Filename.concat
                       (Filename.concat root "_build/default")
                       (Filename.concat scope "generated.ml")
                   && Option.is_some entry.producer)
                 entries)
          then
            failwith
              "scoped nonrecursive inventory lost the declared generated test module")
  | _ :: expected :: sources when sources <> [] ->
      List.iter
        (fun source ->
          match (expected, Artifact.membership ~caps source) with
          | "built", Artifact.Built Artifact.Library | "unknown", Artifact.Unknown -> ()
          | _ -> failwith ("unexpected inventory membership: " ^ source))
        sources
  | _ -> failwith "expected generated ROOT or built/unknown SOURCE..."

let () = run ~caps:(Ox_caps_door.powerbox ())
