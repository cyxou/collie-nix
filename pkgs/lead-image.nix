# Lead collie (ColliePWA) container image — the always-on crew front door,
# published as ghcr.io/cyxou/collie-lead:<collie version> by the bump workflow
# and deployed as a librepod/marketplace app (behind traefik).
#
# The lead aggregates members; its own herd is empty (no herdr in the image —
# tmux is bundled only so the bridge has a local mux to point at).
# Runtime config lands as container env, which beats every file layer
# (bridge/config-source.ts: default < config.toml < process env).
#
# The tmux the bridge points at must actually ANSWER. There is no /tmp in this
# image (and the container runs as 65534, so it cannot make one at /), so tmux
# dies with "no suitable socket path" before any server exists; the bridge then
# marks its own mux disconnected on every poll, and the PWA — whose red-banner
# probe hits this bridge — renders that as a permanent "Herdr is down on the
# host". TMUX_TMPDIR on the state PVC plus one held session keeps a server
# alive; an answering server with an empty herd reads as connected, and the
# banner stays green. busybox is here for the /bin/sh that holds that session.
{
  dockerTools,
  collie,
  tmux,
  busybox,
  cacert,
}:

dockerTools.buildImage {
  name = "collie-lead";
  tag = collie.version;

  copyToRoot = [
    collie
    tmux
    busybox
    cacert
    dockerTools.fakeNss
  ];

  config = {
    Env = [
      # bun needs a writable HOME; /state holds the crew trust store, pairing
      # registry, audit log and push subscriptions — mount a PVC here.
      "HOME=/state"
      # tmux -F listings need a UTF-8 locale: in the C locale tmux sanitizes
      # the 0x1f field separator out of its output and the bridge parses zero
      # rows ("tmux list: output did not parse … 3 lines, 0 rows") — which the
      # PWA renders as the permanent "Herdr is down on the host" banner.
      "LANG=C.UTF-8"
      "COLLIE_STATE_DIR=/state"
      "COLLIE_MUX=tmux"
      # /tmp does not exist and cannot be created at runtime — keep tmux's
      # socket on the PVC instead (see the header note).
      "TMUX_TMPDIR=/state/tmp"
      # bun (BoringSSL) needs the CA bundle pointed at explicitly.
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      # Traefik is another pod, so it reaches this bridge off-loopback.
      "COLLIE_HOST=0.0.0.0"
      "COLLIE_ALLOW_NON_LOOPBACK_BIND=1"
      # The door is traefik's, never tailscale serve.
      "COLLIE_SKIP_SERVE=1"
    ];
    Entrypoint = [
      "/bin/sh"
      "-c"
      # Hold one tmux session open for the bridge to list (a tmux server with
      # zero sessions exits, and a dead mux reads as "Herdr is down" in the
      # PWA), then become the bridge (exec keeps PID 1 signal handling).
      # 2147483647s ≈ 68 years: busybox sleep has no "infinity".
      ''
        mkdir -p "$TMUX_TMPDIR"
        tmux new-session -d -s lead-hold 'sleep 2147483647'
        exec /bin/collie _exec-bridge''
    ];
    User = "65534:65534";
    # org.opencontainers.image.source links the ghcr package to this repo,
    # which is what lets the workflow's GITHUB_TOKEN keep pushing to it.
    Labels = {
      "org.opencontainers.image.source" = "https://github.com/cyxou/collie-nix";
      "org.opencontainers.image.title" = "collie-lead";
      "org.opencontainers.image.description" = "ColliePWA crew lead (https://colliepwa.dev)";
      "org.opencontainers.image.version" = collie.version;
      "org.opencontainers.image.licenses" = "MIT";
    };
  };
}
