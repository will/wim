{ nixpkgs, overlays }:
let inherit (nixpkgs) lib;
in {
  npins-plugins = dir:
    (lib.mapAttrsToList
      (pname: pin:
        (pin // {
          inherit pname;
          optional = true; # make all plugins go into /opt/
          vimPlugin = true; # for .luarc.json to grab the correct dir
          version = pin.version or (builtins.substring 0 8 pin.revision);
        }))
      (import ./${dir}));

  with-system = x:
    lib.foldAttrs lib.mergeAttrs { } (map
      (s:
        builtins.mapAttrs
          (_: v:
            if lib.isFunction v then {
              ${s} = v {
                # pkgs = nixpkgs.legacyPackages.${s};
                pkgs = import nixpkgs {
                  inherit overlays;
                  system = s;
                };
                system = s;
              };
            } else
              v)
          x) [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ]);
}
