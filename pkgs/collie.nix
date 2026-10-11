# Collie, as a Nix package — vendored (MIT) from upstream
# packaging/nix/collie.nix @ ed64718554800bf395c2bf6e7dafd894987daf92
# (the rev our flake input last pinned; diff against upstream master when
# debugging packaging changes).
#
# This derivation WRAPS the release tarball the upstream workflow already built
# and hashed. It does not build collie: `bun install` needs the network and a
# Nix derivation has none, and vendoring every dependency buys nothing over the
# binary the release already publishes and checksums. Version + sha256 live in
# ../sources.json; the bump workflow (scripts/bump.sh) rewrites them on every
# upstream release.
#
# The install layout is the Arch package's layout, and it is load-bearing:
# bridge/root.ts resolves the install root as dirname(dirname(realpath(argv0)))
# and accepts it only when herdr-plugin.toml sits there, so the whole tarball
# root lands in $out/lib/collie and $out/bin/collie is a symlink into it.
# my-nixos' modules/nixos/collie (WorkingDirectory = ${pkg}/lib/collie) relies on
# this too. A bare binary on PATH would resolve its root to $out and serve no
# web/dist.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  sources ? builtins.fromJSON (builtins.readFile ../sources.json),
}:

let
  version = sources.version;

  url = "https://github.com/AltanS/collie/releases/download/v${version}/collie-${version}-linux-x64.tar.gz";
in
if stdenv.hostPlatform.system != "x86_64-linux" then
  throw "collie: only x86_64-linux release payloads are wired up here (linux-x64 tarball); upstream also ships linux-arm64 and darwin-arm64"
else
  stdenv.mkDerivation {
    pname = "collie";
    inherit version;

    src = fetchurl {
      inherit url;
      # Kept hex (base-16), same spelling as upstream's sources.json and the
      # release's own .sha256 asset, so the values compare at a glance.
      sha256 = sources.sha256;
    };

    # The binary is a Bun single-file executable built against glibc, so it
    # carries a /lib64 interpreter and an rpath that no NixOS machine has.
    # autoPatchelfHook rewrites both.
    nativeBuildInputs = [ autoPatchelfHook ];

    dontConfigure = true;
    dontBuild = true;

    # The bundle a Bun single-file executable runs from is embedded in the
    # image, and stripping it produces a binary that no longer starts.
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/collie" "$out/bin"
      cp -R ./. "$out/lib/collie/"
      chmod +x "$out/lib/collie/bin/collie"
      [ -d "$out/lib/collie/scripts" ] && chmod +x "$out/lib/collie/scripts"/*.sh
      ln -s "$out/lib/collie/bin/collie" "$out/bin/collie"

      runHook postInstall
    '';

    # `--version` is the cheapest verb that reads the embedded bundle — it
    # tells us the day autoPatchelfHook (or a nixpkgs change under it) breaks
    # the binary. Same guard upstream ships.
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      echo "collie --version says: $("$out/bin/collie" --version)"
      # Substring match: --version prints e.g. 1.14.2+887a37d (tag + rev).
      "$out/bin/collie" --version | grep -qF -- "${version}"
      runHook postInstallCheck
    '';

    meta = {
      description = "Phone web UI for the AI agents running in your terminal, served over Tailscale";
      homepage = "https://github.com/AltanS/collie";
      license = lib.licenses.mit;
      mainProgram = "collie";
      platforms = [ "x86_64-linux" ];
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  }
