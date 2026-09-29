type 'base t = {
  base : 'base;
  logger : Ox_observability.Logger.t;
  caps : Ox_caps.Cap.all_caps;
}
