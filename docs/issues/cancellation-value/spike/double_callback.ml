let bad (f : (Cancellation.t @ local -> 'a) @ local once) = let _ = Cancellation.with_ f in Cancellation.with_ f
