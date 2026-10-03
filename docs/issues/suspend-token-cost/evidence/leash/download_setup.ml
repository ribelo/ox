let obj fields = `Assoc fields
let str value = `String value
let member key = function `Assoc fields -> List.assoc_opt key fields | _ -> None
let bind = Shim.bind

let call ~(io : Io.t @ yielding) ?session ?(deadline = Shim.Duration.seconds 5) cdp method_ params =
  match Shim.Cdp.call ~io cdp ?session ~deadline method_ params with
  | Ok reply -> (
      match (Shim.Cdp.error_of_reply reply, Shim.Cdp.result reply) with
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
let prepare ~(io : Io.t @ yielding) ~clock ~cdp
    ~(on_target : (string -> unit) @ unyielding) =
  let target = ref None in
  Shim.protect
    ~finally:(fun () ->
      match !target with
      | None -> ()
      | Some target ->
          Shim.cancel_protect (fun () ->
              ignore
                (call ~io cdp ~deadline:(Shim.Duration.ms 500) "Target.closeTarget"
                   (obj [ ("targetId", str target) ]))))
    (fun () ->
      Shim.Timeout.timeout ~io ~clock (Shim.Duration.seconds 5) (fun () ->
          (bind
            (call ~io cdp "Target.createTarget"
              (obj [ ("url", str "chrome://downloads/"); ("background", `Bool true) ])
            ) (fun created ->
          (bind (field "targetId" created) (fun id ->
          Shim.critical_section (fun () -> target := Some id; on_target id);
          (bind
            (call ~io cdp "Target.attachToTarget"
              (obj [ ("targetId", str id); ("flatten", `Bool true) ])
            ) (fun attached ->
          (bind (field "sessionId" attached) (fun session ->
          let rec loaded ~(io : Io.t @ yielding) () =
            (bind
              (call ~io ~session cdp "Runtime.evaluate"
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
              ) (fun json ->
            match Option.bind (member "result" json) (member "value") with
            | Some (`Bool true) -> Ok ()
            | _ ->
                Shim.sleep ~io clock 0.01;
                loaded ~io ()) [@nontail])
          in
          loaded ~io ()) [@nontail])) [@nontail])) [@nontail])) [@nontail])))
