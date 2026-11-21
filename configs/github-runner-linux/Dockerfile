# Image for the containerized Linux GitHub Actions runner on the Mac Studio
# (darwin/services/github-runner-linux.nix). launcher.sh builds it inside the
# runner's Colima VM and tags it with a hash of this file and the build args,
# so editing this file rebuilds the image before the next job.
#
# Base: the official runner image (Ubuntu 24.04; user `runner` with
# passwordless sudo; git, curl, jq, unzip, docker CLI). On top of it, what the
# org's workflows expect from a Linux runner (lapwingtools-rs
# native-platforms.yml and nix.yml): make and a C/C++ toolchain, pkg-config
# with the SQLite headers, rustup, and Nix with flakes.

ARG RUNNER_VERSION
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

ARG NIX_VERSION
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      build-essential ca-certificates libsqlite3-dev pkg-config xz-utils \
 && rm -rf /var/lib/apt/lists/*

# Single-user Nix owned by `runner`. An unprivileged container cannot create
# the namespaces the build sandbox needs, so builds run unsandboxed. The store
# may be a cache volume that later jobs reuse; automatic GC keeps it from
# filling the VM disk.
RUN install -d -m 0755 -o runner -g "$(id -gn runner)" /nix \
 && install -d -m 0755 /etc/nix \
 && printf '%s\n' \
      'experimental-features = nix-command flakes' \
      'sandbox = false' \
      'max-jobs = auto' \
      'min-free = 8589934592' \
      'max-free = 21474836480' \
      > /etc/nix/nix.conf

USER runner
RUN curl --proto '=https' --tlsv1.2 -fsSL "https://releases.nixos.org/nix/nix-${NIX_VERSION}/install" \
      | sh -s -- --no-daemon --no-channel-add --no-modify-profile \
 && curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal --default-toolchain none

ENV PATH=/home/runner/.cargo/bin:/home/runner/.nix-profile/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
