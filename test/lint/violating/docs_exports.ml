(* ^nlintd-k036 *)
module Helper = struct
  let noop _ = Eio.Fiber.yield ()
end

module Alias = Helper
module Included = struct
  include Alias
end
include Included
