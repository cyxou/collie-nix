{
  description = "collie (ColliePWA) release tracking: Nix package + crew lead image, bumped by CI on every upstream release";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      collie = pkgs.callPackage ./pkgs/collie.nix { };
    in
    {
      packages.${system} = {
        inherit collie;
        default = collie;
        lead-image = pkgs.callPackage ./pkgs/lead-image.nix { inherit collie; };
      };
    };
}
