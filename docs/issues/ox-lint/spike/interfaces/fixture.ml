type t = { value : int }
let take_local (x @ local) = x.value
let take_global (x @ global) = x.value
let take_default x = x.value
let take_unique (x @ unique) = x.value
let take_portable (f @ portable) = f ()
let portable_value @ portable = fun () -> ()
