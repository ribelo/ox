let bad (f : (Eio.Cancel.t @ local -> 'a) @ local once) = Eio.Cancel.sub (fun cc -> f cc)
