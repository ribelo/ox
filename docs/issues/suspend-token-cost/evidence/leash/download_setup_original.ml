let obj fields = `Assoc fields
let str value = `String value
let member key = function `Assoc fields -> List.assoc_opt key fields | _ -> None
let ( let* ) = Result.bind

let call ?session ?(deadline = Ox.Duration.seconds 5) cdp method_ params =
  match Cdp.call cdp ?session ~deadline method_ params with
  | Ok reply -> (
      match (Cdp.error_of_reply reply, Cdp.result reply) with
      | None, Some result -> Ok result
      | _ -> Error (`Bootstrap method_))
  | Error _ -> Error (`Bootstrap method_)

let field name json =
  match member name json with
  | Some (`String value) -> Ok value
  | _ -> Error (`Bootstrap ("missing " ^ name))

(* daily-c4cl: Chrome 152.0.7977.64's DevToolsDownloadManagerDelegate does not forward
   SupportsHistoryLoading (upstream bug 556160935, fixed by Chromium commit
   34fe0e520e143149b4b8a3faf3736af66442544a). Installing it before persisted History
   and the in-progress cache reconcile crashes Chrome on the next download. The
   downloads page drops [loading] only after its backend sends the history list.
   This is a readiness acknowledgement, not a startup delay. Remove this bootstrap
   when the supported Chrome versions all contain the upstream fix. *)
let prepare ~clock ~cdp ~on_target =
  let target = ref None in
  Fun.protect
    ~finally:(fun () ->
      Option.iter
        (fun target ->
          Eio.Cancel.protect (fun () ->
              ignore
                (call cdp ~deadline:(Ox.Duration.ms 500) "Target.closeTarget"
                   (obj [ ("targetId", str target) ]))))
        !target)
    (fun () ->
      Ox.Timeout.timeout ~clock (Ox.Duration.seconds 5) (fun () ->
          let* created =
            call cdp "Target.createTarget"
              (obj [ ("url", str "chrome://downloads/"); ("background", `Bool true) ])
          in
          let* id = field "targetId" created in
          target := Some id;
          on_target id;
          let* attached =
            call cdp "Target.attachToTarget"
              (obj [ ("targetId", str id); ("flatten", `Bool true) ])
          in
          let* session = field "sessionId" attached in
          let rec loaded () =
            let* json =
              call ~session cdp "Runtime.evaluate"
                (obj
                   [
                     ( "expression",
                       str
                         "document.readyState === 'complete' && \
                          !!customElements.get('downloads-manager') && \
                          !!document.querySelector('downloads-manager') && \
                          !document.querySelector('downloads-manager').hasAttribute('loading')"
                     );
                     ("returnByValue", `Bool true);
                   ])
            in
            match Option.bind (member "result" json) (member "value") with
            | Some (`Bool true) -> Ok ()
            | _ ->
                Eio.Time.sleep clock 0.01;
                loaded ()
          in
          loaded ()))
