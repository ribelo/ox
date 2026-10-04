(* Throwaway API expansion; this file is not a production dependency. *)
module Const = struct include Mode.Alloc.Const end
module Alloc = struct include Mode.Alloc end
module Locality = struct include Mode.Locality end
module Moda = struct include Mode.Modality.Const end
module Modality = struct include Mode.Modality end
module Locality_const = struct include Mode.Locality.Const end
module Alloc_axis = struct include Mode.Alloc.Axis end
