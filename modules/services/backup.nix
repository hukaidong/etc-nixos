{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.kaidong-desktop.services.davMail-backup;
in
{
  options.kaidong-desktop.services.davMail-backup = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.kaidong-desktop.services.davMail.enable;
      description = "Enable DavMail backup service";
    };
  };

  config = lib.mkIf cfg.enable {
    services.borgbackup.jobs.mail-backup = {
      paths = [ "/home/kaidong/.local/Mail" ];

      # Local backup to /mnt/datahdd
      repo = "/mnt/datahdd/borg-backups/mail";

      # Encrypted backup using repokey with blake2
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat /run/secrets/borg-passphrase";
      };

      # Compression to save space
      compression = "auto,zstd";

      # Run daily at 2 AM
      startAt = "02:00";

      # Keep backups for reasonable time periods
      prune.keep = {
        daily = 7;
        weekly = 4;
        monthly = 6;
        yearly = 1;
      };

      # Exclude common cache and temporary files
      exclude = [
        "*/cache/*"
        "*/tmp/*"
        "*/.cache/*"
        "*/Cache/*"
      ];

      # Additional creation arguments for verbose output
      extraCreateArgs = "--verbose --stats --checkpoint-interval 600";

      # Prune old archives automatically
      extraPruneArgs = "--verbose --stats";

      # Pre-backup script to ensure destination exists
      preHook = ''
        # Ensure backup destination directory exists
        mkdir -p /mnt/datahdd/borg-backups
      '';

      # Post-backup notification
      postHook = ''
        echo "Mail backup completed successfully at $(date)"
      '';
    };

    # SOPS secret for Borg passphrase
    sops.secrets.borg-passphrase = {
      sopsFile = ../../secrets/secrets.yaml;
      mode = "0400";
      owner = "root";
      group = "root";
    };

    # Ensure borgbackup is available in the system
    environment.systemPackages = with pkgs; [
      borgbackup
    ];
  };
}
