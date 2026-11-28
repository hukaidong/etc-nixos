# The Linux runner's image (../github-runner-linux.nix), built by Nix and
# pinned by flake.lock like the rest of this machine. Besides `imageName` and
# `imageTag`, like any streamLayeredImage, it has `home`, the jobs' home
# directory.
#
# This Mac has no Linux builder, so the image only uses Linux packages that
# cache.nixos.org has (from `linuxPkgs`), and everything else is
# platform-independent glue built here: symlinks, text files, the image's top
# layer and the script that streams the image.
{
  lib,
  dockerTools,
  runCommandLocal,
  shellcheck-minimal,
  stdenv,
  writeTextFile,
  writers,
  # nixpkgs for the Linux machine the image runs on.
  linuxPkgs,
}:
let
  # Programs on the jobs' PATH: what the org's workflows (lapwingtools-rs
  # native-platforms.yml, nix.yml, bump-version.yml) expect of a Linux runner,
  # plus the usual shell tools. gcc's wrapper includes binutils (nm, ld, ar).
  tools = map lib.getBin (
    with linuxPkgs;
    [
      bashInteractive
      coreutils
      findutils
      diffutils
      gnugrep
      gnused
      gawk
      gnupatch
      which
      procps
      gnutar
      gzip
      bzip2
      xz
      zstd
      unzip
      curl
      git
      jq
      gcc
      gnumake
      pkg-config
      sqlite
      rustup
      nix
    ]
  );
  sqliteDev = lib.getDev linuxPkgs.sqlite;

  # Jobs run as this unprivileged user, like on GitHub's hosted runners, so
  # file permissions mean in a job what they mean elsewhere (root reads a
  # mode-000 file, and tests that expect EACCES fail). It owns the Nix store,
  # its home (rustup, cargo) and the runner's directory; there is no sudo.
  jobUser = {
    name = "runner";
    uid = 1001;
    gid = 1001;
  };
  home = "/home/${jobUser.name}";
  runnerRoot = "/runner";

  # Registers an ephemeral runner and runs it for one job; see the file. The
  # shebang and the store paths are Linux ones, but the file is plain text,
  # so it is written (and shellchecked) here.
  entrypoint = writeTextFile {
    name = "github-runner-linux-entrypoint";
    executable = true;
    text = ''
      #!${linuxPkgs.runtimeShell}
      set -o errexit -o nounset -o pipefail
      GITHUB_RUNNER=${linuxPkgs.github-runner}
    ''
    + builtins.readFile ../../../../configs/github-runner-linux/entrypoint.sh;
    checkPhase = ''
      ${stdenv.shellDryRun} "$target"
      ${lib.getExe shellcheck-minimal} "$target"
    '';
  };

  # The image's root file system, as symlinks into the Linux store paths. Its
  # closure is everything the image uses, so includeNixDB below registers all
  # of it in the image's Nix database: Nix in a job then substitutes nothing
  # the image has, and its garbage collector (a cache volume can keep /nix)
  # never deletes the runner or its tools.
  rootfs = runCommandLocal "github-runner-linux-rootfs" { } ''
    shopt -s nullglob
    mkdir -p $out/usr/bin $out/usr/include $out/usr/lib/pkgconfig \
      $out/usr/libexec/github-runner $out/etc/ssl/certs

    # Of two programs with the same name, the earlier package's wins
    # (coreutils' kill and uptime over procps').
    for pkg in ${lib.escapeShellArgs tools}; do
      for program in "$pkg"/bin/*; do
        name=''${program##*/}
        if [[ ! -e $out/usr/bin/$name && ! -L $out/usr/bin/$name ]]; then
          ln -s "$program" "$out/usr/bin/$name"
        fi
      done
    done

    # SQLite's development files where Debian's libsqlite3-dev puts them,
    # for pkg-config (PKG_CONFIG_PATH) and the compiler (CPATH).
    ln -s ${sqliteDev}/include/* $out/usr/include/
    ln -s ${sqliteDev}/lib/pkgconfig/sqlite3.pc $out/usr/lib/pkgconfig/

    # CA certificates at the paths Nix, Debian and OpenSSL look at.
    ln -s ${linuxPkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/
    ln -s ca-bundle.crt $out/etc/ssl/certs/ca-certificates.crt
    ln -s certs/ca-bundle.crt $out/etc/ssl/cert.pem

    ln -s ${entrypoint} $out/usr/libexec/github-runner/entrypoint
  '';

  etcFiles = {
    passwd = ''
      root:x:0:0:root:/root:/bin/bash
      ${jobUser.name}:x:${toString jobUser.uid}:${toString jobUser.gid}:${jobUser.name}:${home}:/bin/bash
      nobody:x:65534:65534:nobody:/var/empty:/bin/false
    '';
    group = ''
      root:x:0:
      ${jobUser.name}:x:${toString jobUser.gid}:
      nobody:x:65534:
    '';
    "nsswitch.conf" = ''
      passwd: files
      group: files
      shadow: files
      hosts: files dns
    '';
    # Single-user Nix, owned by the job user. An unprivileged container
    # cannot create the namespaces the build sandbox needs, so builds run
    # unsandboxed, without build users. The store may be a cache volume that
    # later jobs reuse; automatic GC keeps it from filling the VM disk.
    "nix/nix.conf" = ''
      experimental-features = nix-command flakes
      sandbox = false
      build-users-group =
      max-jobs = auto
      min-free = 8589934592
      max-free = 21474836480
    '';
  };

  # cache.nixos.org's Linux store paths sit in this Mac's case-insensitive
  # store with Nix's case hack: of two names in a directory that differ only
  # in case (terminfo's a/ and A/, some linux-headers files), the later one is
  # stored as `<name>~nix~case~hack~<n>`. The image needs the real names, which
  # the hashes in its Nix database describe, so this wraps the upstream stream
  # script to strip the suffix from every name it archives. Without the case
  # hack (a case-sensitive store) it changes nothing.
  caseSensitiveStreamScript =
    upstream:
    writers.writePython3 "stream-case-sensitive" { } ''
      import runpy
      import tarfile

      CASE_HACK = "~nix~case~hack~"
      gettarinfo = tarfile.TarFile.gettarinfo


      def gettarinfo_without_case_hack(self, *args, **kwargs):
          info = gettarinfo(self, *args, **kwargs)
          info.name = "/".join(
              part.split(CASE_HACK)[0] for part in info.name.split("/")
          )
          return info


      tarfile.TarFile.gettarinfo = gettarinfo_without_case_hack
      runpy.run_path(
          "${upstream}",
          run_name="__main__",
      )
    '';
in
# A script that writes the image to stdout in `docker load` format; the
# layers are the store paths themselves, assembled when it runs. Its tag is
# a hash of the image's contents and config.
(dockerTools.streamLayeredImage {
  name = "github-runner-linux";
  architecture = linuxPkgs.go.GOARCH;
  contents = [ rootfs ];
  includeNixDB = true;
  # The store layers, /nix and /nix/store belong to the job user, which
  # runs Nix single-user.
  inherit (jobUser) uid gid;
  uname = jobUser.name;
  gname = jobUser.name;
  # Writable directories and the /etc files. They are created here as
  # the building user, and the top layer is archived under fakeroot, so
  # they belong to root in the container unless fakeRootCommands gives
  # them away. The home's .rustup and .cargo exist so that docker, which
  # fills an empty cache volume from the image, gives the volume their
  # owner.
  extraCommands = ''
    ln -s usr/bin bin
    mkdir -p usr/local/bin var home
    mkdir -m 1777 tmp var/tmp
    mkdir -m 0555 var/empty
    mkdir -m 0700 root .${home}
    mkdir -m 0755 .${home}/.rustup .${home}/.cargo .${runnerRoot}
  ''
  + lib.concatStrings (
    lib.mapAttrsToList (name: text: ''
      mkdir -p "$(dirname etc/${name})"
      printf '%s' ${lib.escapeShellArg text} > etc/${name}
    '') etcFiles
  );
  # includeNixDB's database (and an empty nix/store) are in this layer
  # too, and would otherwise hand /nix back to root.
  fakeRootCommands = ''
    chown -R ${toString jobUser.uid}:${toString jobUser.gid} nix .${home} .${runnerRoot}
  '';
  config = {
    Entrypoint = [ "${entrypoint}" ];
    User = "${toString jobUser.uid}:${toString jobUser.gid}";
    WorkingDir = home;
    Env = [
      "PATH=${home}/.cargo/bin:${home}/.nix-profile/bin:/usr/local/bin:/usr/bin"
      "HOME=${home}"
      "USER=${jobUser.name}"
      "LANG=C.UTF-8"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
      "PKG_CONFIG_PATH=/usr/lib/pkgconfig"
      "CPATH=/usr/include"
      # Outside a Nix build, gcc's wrapper knows only its own and glibc's
      # libraries. gcc turns LIBRARY_PATH into -L flags, and for a store
      # directory the wrapper also adds an rpath, so the test binaries
      # that link -lsqlite3 run too.
      "LIBRARY_PATH=${lib.getLib linuxPkgs.sqlite}/lib"
      # Where nixpkgs' runner wrappers keep the runner's state and
      # configuration (default ~/.github-runner); the jobs' work tree is
      # its _work.
      "RUNNER_ROOT=${runnerRoot}"
      # Diagnostic logs stay in files in the container.
      "ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=false"
    ];
  };
}).overrideAttrs
  (old: {
    streamScript = caseSensitiveStreamScript old.streamScript;
    passthru = old.passthru // {
      inherit home;
    };
  })
