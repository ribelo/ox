[@@@ox_lint.fixture "ox-caps-signature: deliberate negative fixture"]

let ambient : Ox_caps.Cap.fork = Obj.magic ()
let violation () = Ox_caps.Cap_unix.fork ~caps:ambient ()

let impostor ~(caps : < fork : int >) () =
  ignore caps;
  Unix.fork ()

let minted () =
  let caps = Ox_caps_door.powerbox () in
  Ox_caps.Cap_unix.fork ~caps ()
