{ nixpkgs, overlays }:
let
  inherit (nixpkgs) lib;
in
{
  with-system =
    x:
    lib.foldAttrs lib.mergeAttrs { } (
      map
        (
          s:
          builtins.mapAttrs (
            _: v:
            if lib.isFunction v then
              {
                ${s} = v {
                  # pkgs = nixpkgs.legacyPackages.${s};
                  pkgs = import nixpkgs {
                    inherit overlays;
                    system = s;
                  };
                  system = s;
                };
              }
            else
              v
          ) x
        )
        [
          "x86_64-linux"
          "x86_64-darwin"
          "aarch64-linux"
          "aarch64-darwin"
        ]
    );
}
