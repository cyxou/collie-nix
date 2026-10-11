# collie-nix

Nix packaging for [collie](https://github.com/AltanS/collie) — **ColliePWA**
(https://colliepwa.dev), the phone UI for the AI agents in your terminal —
tracking **every** upstream release.

A GitHub Action checks for a new release every 2 hours. It verifies the
tarball against the release's published `.sha256`, rewrites `sources.json`,
builds (the build runs `collie --version`), commits, tags `vX.Y.Z`, and pushes
the crew-lead image.

## Use

```nix
inputs.collie-nix = {
  url = "github:cyxou/collie-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
# overlay
collie = inputs.collie-nix.packages.${final.stdenv.hostPlatform.system}.collie;
```

Update: `nix flake update collie-nix`.

Lead image: `ghcr.io/cyxou/collie-lead:<collie version>` (also `:latest`).

x86_64-linux only.

`pkgs/collie.nix` is vendored from upstream `packaging/nix/collie.nix` (MIT).
Upstream's own flake wraps releases too, but its `sources.json` skips
releases, which is why this repo exists.
