{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kaidong-desktop.services.githubRunners;
  lcfg = cfg.linux;

  user = "_github-runner-linux";
  group = user;
  runnerName = "${cfg.name}-linux";
  # Same layout nix-darwin's github-runner module uses for the macOS runner.
  stateDir = "/var/lib/github-runners/${runnerName}";
  logDir = "/var/log/github-runners/${runnerName}";
  # Colima's directory, with Lima's in its _lima. Colima ignores COLIMA_HOME
  # unless it exists (and falls back to ~/.colima), so it is the state
  # directory itself, which activation creates; a subdirectory would also
  # make the VM's sockets too long (see the assertion).
  colimaHome = stateDir;
  # The VM's longest unix socket, Lima's for Colima's user-v2 network, at the
  # path Lima checks: /var is a symlink to /private/var.
  longestSocket =
    lib.optionalString (lib.hasPrefix "/var/" stateDir) "/private"
    + "${colimaHome}/_lima/_networks/user-v2/user-v2_qemu.sock";
  install = "${pkgs.coreutils}/bin/install";

  # aarch64 or x86_64: the VM, the image and the runner's architecture label
  # all follow this Mac's CPU.
  cpu = pkgs.stdenv.hostPlatform.parsed.cpu.name;

  dockerEnv = {
    HOME = stateDir;
    DOCKER_CONFIG = "${stateDir}/docker";
  };

  # --- The runner image ------------------------------------------------------
  #
  # Built by Nix and pinned by flake.lock, like the rest of this machine. This
  # Mac has no Linux builder, so the image only uses Linux packages that
  # cache.nixos.org has, and everything else is platform-independent glue
  # built here: symlinks, text files, the image's top layer and the script
  # that streams the image.

  # Plain nixpkgs, without this flake's overlays or config, so every Linux
  # store path is one Hydra built.
  linuxPkgs = inputs.nixpkgs.legacyPackages."${cpu}-linux";

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
  entrypoint = pkgs.writeTextFile {
    name = "github-runner-linux-entrypoint";
    executable = true;
    text = ''
      #!${linuxPkgs.runtimeShell}
      set -o errexit -o nounset -o pipefail
      GITHUB_RUNNER=${linuxPkgs.github-runner}
    ''
    + builtins.readFile ../../../configs/github-runner-linux/entrypoint.sh;
    checkPhase = ''
      ${pkgs.stdenv.shellDryRun} "$target"
      ${lib.getExe pkgs.shellcheck-minimal} "$target"
    '';
  };

  # The image's root file system, as symlinks into the Linux store paths. Its
  # closure is everything the image uses, so includeNixDB below registers all
  # of it in the image's Nix database: Nix in a job then substitutes nothing
  # the image has, and its garbage collector (a cache volume can keep /nix)
  # never deletes the runner or its tools.
  rootfs = pkgs.runCommandLocal "github-runner-linux-rootfs" { } ''
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
    pkgs.writers.writePython3 "stream-case-sensitive" { } ''
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

  # A script that writes the image to stdout in `docker load` format; the
  # layers are the store paths themselves, assembled when it runs. Its tag is
  # a hash of the image's contents and config.
  image =
    (pkgs.dockerTools.streamLayeredImage {
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
      });

  launcher = pkgs.writeShellApplication {
    name = "github-runner-linux";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      docker
      jq
    ];
    runtimeEnv = {
      ORG = cfg.org;
      RUNNER_NAME = runnerName;
      RUNNER_GROUP = lcfg.runnerGroup;
      RUNNER_LABELS = lib.concatStringsSep "," lcfg.extraLabels;
      TOKEN_FILE = config.sops.secrets."github-runner-token-linux".path;
      IMAGE_STREAM = "${image}";
      IMAGE_NAME = image.imageName;
      IMAGE_TAG = image.imageTag;
      IMAGE_HOME = home;
      CACHE_VOLUMES = lib.boolToString lcfg.cacheVolumes;
    };
    text = builtins.readFile ../../../configs/github-runner-linux/launcher.sh;
  };
in
{
  options.kaidong-desktop.services.githubRunners.linux = {
    enable = lib.mkEnableOption ''
      the containerized Linux runner: a Colima VM plus a launcher that runs
      every job in a fresh container, from an image built by Nix, as an
      ephemeral runner registered for that job (labels self-hosted, Linux,
      ARM64). Both are boot-time launchd daemons running as the hidden
      `${user}` user
    '';

    extraLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Labels added to the default self-hosted, Linux and ARM64.";
    };

    runnerGroup = lib.mkOption {
      type = lib.types.str;
      default = "Default";
      description = "Organization runner group the ephemeral runners join.";
    };

    cpus = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "CPUs of the Colima VM.";
    };

    memory = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Memory of the Colima VM, in GiB.";
    };

    disk = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = "Disk of the Colima VM, in GiB. Sparse, and it can only grow.";
    };

    vmType = lib.mkOption {
      type = lib.types.enum [
        "vz"
        "qemu"
      ];
      default = "vz";
      description = ''
        Colima VM backend: Apple's Virtualization.framework (`vz`, faster) or
        QEMU with HVF. Switch to `qemu` if the VM will not start from a
        launchd daemon; existing VMs keep their type until
        `colima delete` (run as `${user}` with COLIMA_HOME=${colimaHome}).
      '';
    };

    cacheVolumes = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep the Nix store, rustup toolchains and cargo's registry in volumes
        that later jobs reuse. Jobs start much faster, but they are no longer
        isolated from what earlier jobs left in those directories.
      '';
    };
  };

  config = lib.mkIf lcfg.enable {
    assertions = [
      {
        # macOS caps a unix socket path below UNIX_PATH_MAX, 104 bytes.
        assertion = lib.stringLength longestSocket < 104;
        message = "kaidong-desktop.services.githubRunners.name is too long for the Linux runner's VM sockets: ${longestSocket} is ${toString (lib.stringLength longestSocket)} bytes, macOS allows 103.";
      }
    ];

    users.users.${user} = {
      uid = lib.mkDefault 540;
      gid = config.users.groups.${group}.gid;
      home = stateDir;
      createHome = false;
      shell = "/bin/bash";
      description = "GitHub Actions runner (Linux VM)";
    };
    users.groups.${group} = {
      gid = lib.mkDefault 540;
      description = "GitHub Actions runner (Linux VM)";
    };
    users.knownUsers = [ user ];
    users.knownGroups = [ group ];

    sops.secrets."github-runner-token-linux" = {
      key = cfg.tokenSecret;
      owner = user;
      mode = "0400";
    };

    # The daemons' directories must exist, owned by the service user, before
    # launchd starts them.
    system.activationScripts.launchd.text = lib.mkBefore ''
      echo >&2 "setting up GitHub Runner '${runnerName}'..."
      ${install} -d -m 0755 /var/lib/github-runners /var/log/github-runners
      ${install} -d -m 0700 -o ${user} -g ${group} ${stateDir}
      ${install} -d -m 0750 -o ${user} -g ${group} ${logDir}
    '';

    # The VM: Colima running Docker, with no host directory mounted into it.
    launchd.daemons.github-runner-linux-vm = {
      path =
        (with pkgs; [
          colima
          coreutils
          curl
          docker
          openssh
        ])
        ++ [
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      environment = dockerEnv // {
        COLIMA_HOME = colimaHome;
      };
      script = ''
        exec colima start default --foreground \
          --save-config=false --activate=false --ssh-config=false \
          --runtime docker --arch ${cpu} \
          --vm-type ${lcfg.vmType} --cpus ${toString lcfg.cpus} \
          --memory ${toString lcfg.memory} --disk ${toString lcfg.disk} \
          --mount none
      '';
      serviceConfig = {
        UserName = user;
        GroupName = group;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        # Time for Colima to shut the VM down cleanly.
        ExitTimeOut = 60;
        ProcessType = "Interactive";
        SoftResourceLimits.NumberOfFiles = 4096;
        WorkingDirectory = stateDir;
        StandardOutPath = "${logDir}/vm.log";
        StandardErrorPath = "${logDir}/vm.log";
      };
    };

    # One ephemeral runner per job; KeepAlive starts the next one.
    launchd.daemons.github-runner-linux = {
      environment = dockerEnv // {
        DOCKER_HOST = "unix://${colimaHome}/default/docker.sock";
      };
      command = lib.getExe launcher;
      serviceConfig = {
        UserName = user;
        GroupName = group;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        ProcessType = "Interactive";
        WorkingDirectory = stateDir;
        StandardOutPath = "${logDir}/runner.log";
        StandardErrorPath = "${logDir}/runner.log";
      };
    };
  };
}
