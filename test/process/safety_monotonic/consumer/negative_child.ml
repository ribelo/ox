let bad_child ~caps ~sw ~mgr (clock : _ Eio.Time.clock) =
  Ox_process.Child.spawn ~caps ~sw ~clock ~mgr ~argv:[ "/bin/sh" ] ~grace:Ox.Duration.zero
    ~fds:[] ()
