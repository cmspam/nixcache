{
  description = "CI build flake - builds and caches all derivations for zephyrus and gamepc";

  # ============================================================
  # Cache configuration - pull from all known good caches first
  # so we don't redundantly rebuild anything already cached.
  # ============================================================
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://attic.xuyh0120.win/lantian"
      "https://jovian-experiments.cachix.org"
      "https://cmspam.cachix.org"
      "https://lanzaboote.cachix.org"
      "https://nix-community.cachix.org"
      "https://cuda-maintainers.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "jovian-experiments.cachix.org-1:TyDJIG9AdB5uEAHVAVCjXU1qKBZkCIvqj4rDRz5/sfY="
      "cmspam.cachix.org-1:Xd8Ff8s65DuMHtLf+kpSsdBB62gokpj5PQWA74NU++s="
      "lanzaboote.cachix.org-1:Nt9//zGmqkg1k5iu+B3bkj3OmHKjSw9pvf3faffLLNk="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCUSeBo="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  # ============================================================
  # Inputs - mirrors your real flake exactly
  # ============================================================
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
    nixos-hardware.url = "github:nixos/nixos-hardware";

    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    qemu-patched.url = "github:cmspam/qemu-patched";

    inputactions = {
      url = "git+https://github.com/taj-ny/InputActions?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    bbr_classic = {
      url = "github:cmspam/bbr_classic";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # ============================================================
  # Outputs
  # ============================================================
  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-stable,
      nixos-hardware,
      lanzaboote,
      jovian,
      nix-cachyos-kernel,
      qemu-patched,
      bbr_classic,
      inputactions,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      pkgs-stable = import nixpkgs-stable {
        inherit system;
        config.allowUnfree = true;
      };

      # Helper: build a NixOS system with the CachyOS kernel overlay + qemu overlay applied
      mkSystem =
        modules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs pkgs-stable; };
          modules =
            [
              lanzaboote.nixosModules.lanzaboote
              jovian.nixosModules.default
              bbr_classic.nixosModules.default
              (
                { pkgs, ... }:
                {
                  nixpkgs.overlays = [
                    nix-cachyos-kernel.overlays.pinned
                    qemu-patched.overlays.default
                  ];
                  nixpkgs.config.allowUnfree = true;
                  nix.settings.experimental-features = [
                    "nix-command"
                    "flakes"
                  ];
                }
              )
            ]
            ++ modules;
        };

      # --------------------------------------------------------
      # Inline stub modules for each host.
      # These replicate every option that affects what gets built
      # without encoding any personal/identifying info (no real
      # UUIDs, disk labels, user names, key files, etc.).
      # --------------------------------------------------------

      zephyrusModules =
        [
          nixos-hardware.nixosModules.asus-zephyrus-ga402x-nvidia

          # --- Fake hardware configuration (no real UUIDs) ------
          (
            { lib, modulesPath, ... }:
            {
              imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
              boot.initrd.availableKernelModules = [
                "nvme"
                "xhci_pci"
                "thunderbolt"
                "usb_storage"
                "usbhid"
                "sd_mod"
                "rtsx_pci_sdmmc"
              ];
              boot.kernelModules = [ "kvm-amd" ];
              boot.extraModulePackages = [ ];
              # Fake root fs so NixOS config evaluates cleanly
              fileSystems."/" = {
                device = "/dev/sda1";
                fsType = "ext4";
              };
              fileSystems."/efi" = {
                device = "/dev/sda2";
                fsType = "vfat";
              };
              swapDevices = [ ];
              nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
              hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
            }
          )

          # --- Boot (Zephyrus) -----------------------------------
          (
            { config, pkgs, lib, ... }:
            {
              boot = {
                loader.systemd-boot.enable = lib.mkForce false;
                loader.efi.canTouchEfiVariables = true;
                loader.efi.efiSysMountPoint = "/efi";

                lanzaboote = {
                  enable = true;
                  pkiBundle = "/var/lib/sbctl";
                };

                # CachyOS zen4 LTO kernel (the expensive compile target)
                kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-zen4;

                kernelParams = [
                  "i8042.reset=1"
                  "i8042.nomux=1"
                  "asus_wmi.kbd_rgb_mode=0"
                  "amdgpu.gpu_recovery=1"
                  "amdgpu.dcdebugmask=0x10"
                ];

                initrd.availableKernelModules = [
                  "atkbd"
                  "i8042"
                ];
                initrd.kernelModules = [
                  "atkbd"
                  "i8042"
                ];

                initrd.systemd.enable = true;
                supportedFilesystems = [ "fuse" ];
              };

              environment.systemPackages = [ pkgs.sbctl ];
            }
          )

          # --- Hardware (Zephyrus) - NVIDIA + ASUS services ------
          (
            { config, lib, pkgs, ... }:
            {
              services.fstrim.enable = true;
              hardware.bluetooth.enable = true;
              hardware.bluetooth.powerOnBoot = true;
              services.hardware.bolt.enable = true;

              services.xserver.videoDrivers = [ "nvidia" ];
              hardware.nvidia = {
                open = true;
                nvidiaSettings = true;
                package =
                  let
                    base = config.boot.kernelPackages.nvidiaPackages.latest;
                    cachyos-nvidia-patch = pkgs.fetchpatch {
                      url = "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/nvidia/nvidia-utils/kernel-6.19.patch";
                      sha256 = "sha256-YuJjSUXE6jYSuZySYGnWSNG5sfVei7vvxDcHx3K+IN4=";
                    };
                    driverAttr = if config.hardware.nvidia.open then "open" else "bin";
                  in
                  base
                  // {
                    ${driverAttr} = base.${driverAttr}.overrideAttrs (oldAttrs: {
                      patches = (oldAttrs.patches or [ ]) ++ [ cachyos-nvidia-patch ];
                    });
                  };
                powerManagement.enable = true;
                powerManagement.finegrained = true;
                modesetting.enable = true;
                dynamicBoost.enable = lib.mkForce true;
              };

              services.supergfxd.enable = true;
              services.asusd.enable = true;

              environment.systemPackages =
                let
                  nvidia-run = pkgs.writeShellScriptBin "nvidia-run" ''
                    export __NV_PRIME_RENDER_OFFLOAD=1
                    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
                    export __GLX_VENDOR_LIBRARY_NAME=nvidia
                    export __VK_LAYER_NV_optimus=NVIDIA_only
                    exec "$@"
                  '';
                  amd-run = pkgs.writeShellScriptBin "amd-run" ''
                    export DRI_PRIME=1
                    exec "$@"
                  '';
                in
                with pkgs;
                [
                  nvidia-run
                  amd-run
                  supergfxctl
                  supergfxctl-plasmoid
                  asusctl
                ];

              boot.kernel.sysctl."kernel.sysrq" = 1;
            }
          )

          # --- BBR kernel modules (built against zen4 kernel) ---
          bbrModule

          # --- Hostname ---
          { networking.hostName = "zephyrus"; }
        ]
        # --- Profiles (concatenated, not nested) ---------------
        ++ zephyrusProfileModules;

      gamePCModules =
        [
          # --- Fake hardware configuration ----------------------
          (
            { lib, modulesPath, ... }:
            {
              imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
              boot.initrd.availableKernelModules = [
                "nvme"
                "xhci_pci"
                "ahci"
                "usbhid"
                "usb_storage"
                "sd_mod"
              ];
              boot.extraModulePackages = [ ];
              fileSystems."/" = {
                device = "/dev/sda1";
                fsType = "ext4";
              };
              fileSystems."/efi" = {
                device = "/dev/sda2";
                fsType = "vfat";
              };
              swapDevices = [ ];
              nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
              hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
            }
          )

          # --- Boot (gamepc) ------------------------------------
          (
            { config, pkgs, lib, ... }:
            {
              boot = {
                plymouth.enable = true;
                loader.systemd-boot.enable = lib.mkForce false;
                loader.systemd-boot.consoleMode = "max";
                loader.efi.canTouchEfiVariables = true;
                loader.efi.efiSysMountPoint = "/efi";

                lanzaboote = {
                  enable = true;
                  pkiBundle = "/var/lib/sbctl";
                };

                # CachyOS x86_64-v3 LTO kernel
                kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-x86_64-v3;
                kernelParams = [ "quiet" ];
                initrd.systemd.enable = true;
                supportedFilesystems = [ "fuse" ];
                consoleLogLevel = 0;
              };
            }
          )

          # --- Hardware (gamepc) - NVIDIA RTX 4090 --------------
          (
            { config, lib, pkgs, ... }:
            {
              services.fstrim.enable = true;
              hardware.bluetooth.enable = true;
              hardware.bluetooth.powerOnBoot = true;
              hardware.xone.enable = true;

              services.xserver.videoDrivers = [ "nvidia" ];
              hardware.nvidia = {
                open = true;
                nvidiaSettings = true;
                package =
                  let
                    base = config.boot.kernelPackages.nvidiaPackages.latest;
                    cachyos-nvidia-patch = pkgs.fetchpatch {
                      url = "https://raw.githubusercontent.com/CachyOS/CachyOS-PKGBUILDS/master/nvidia/nvidia-utils/kernel-6.19.patch";
                      sha256 = "sha256-YuJjSUXE6jYSuZySYGnWSNG5sfVei7vvxDcHx3K+IN4=";
                    };
                    driverAttr = if config.hardware.nvidia.open then "open" else "bin";
                  in
                  base
                  // {
                    ${driverAttr} = base.${driverAttr}.overrideAttrs (oldAttrs: {
                      patches = (oldAttrs.patches or [ ]) ++ [ cachyos-nvidia-patch ];
                    });
                  };
                powerManagement.enable = true;
                modesetting.enable = true;
              };

              boot.kernel.sysctl."kernel.sysrq" = 1;
            }
          )

          # --- BBR kernel modules (built against x86_64-v3 kernel) ---
          bbrModule

          # --- Hostname ---
          { networking.hostName = "gamepc"; }
        ]
        # --- Profiles (concatenated, not nested) ---------------
        ++ gamePCProfileModules;

      # --------------------------------------------------------
      # Profiles - shared between both hosts
      # --------------------------------------------------------

      # Profiles zephyrus uses that gamepc doesn't: touchpad, sshd removed from
      # gamepc isn't used... actually both use sshd. Let's include all shared ones.
      sharedProfileModules = [
        # Audio
        (
          { ... }:
          {
            services.pulseaudio.enable = false;
            security.rtkit.enable = true;
            services.pipewire = {
              enable = true;
              alsa.enable = true;
              alsa.support32Bit = true;
              pulse.enable = true;
            };
          }
        )

        # Printing
        { services.printing.enable = true; }

        # Fonts
        (
          { pkgs, ... }:
          {
            fonts.packages = with pkgs; [
              inter
              roboto
              source-sans
              source-serif
              noto-fonts-cjk-sans
              noto-fonts-cjk-serif
              nerd-fonts.jetbrains-mono
              nerd-fonts.fira-code
              noto-fonts-color-emoji
              noto-fonts
              liberation_ttf
              corefonts
              vista-fonts
              google-fonts
              font-awesome
            ];
            fonts.fontconfig = {
              enable = true;
              antialias = true;
              hinting = {
                enable = true;
                style = "slight";
                autohint = false;
              };
              subpixel = {
                rgba = "rgb";
                lcdfilter = "default";
              };
              defaultFonts = {
                sansSerif = [ "Inter" "DejaVu Sans" ];
                serif = [ "Liberation Serif" "DejaVu Serif" ];
                monospace = [ "JetBrainsMono Nerd Font" "DejaVu Sans Mono" ];
                emoji = [ "Noto Color Emoji" ];
              };
            };
          }
        )

        # Locale (Japan)
        (
          { pkgs, ... }:
          {
            time.timeZone = "Asia/Tokyo";
            i18n.defaultLocale = "en_US.UTF-8";
            i18n.inputMethod = {
              type = "fcitx5";
              enable = true;
              fcitx5.addons = with pkgs; [
                fcitx5-mozc
                kdePackages.fcitx5-qt
                fcitx5-gtk
              ];
              fcitx5.waylandFrontend = true;
            };
          }
        )

        # KDE Plasma desktop
        (
          { pkgs, ... }:
          {
            services.xserver = {
              enable = true;
              xkb = { layout = "us"; variant = ""; };
            };
            services.displayManager.plasma-login-manager.enable = true;
            services.desktopManager.plasma6.enable = true;
            xdg.portal.enable = true;
            environment.systemPackages = with pkgs; [
              kdePackages.kate
              kdePackages.qtdeclarative
              kdePackages.kwin
              tesseract
              (kdePackages.spectacle.override {
                tesseractLanguages = [ "eng" "jpn" "jpn_vert" "mon" ];
              })
            ];
          }
        )

        # Gaming
        (
          { pkgs, ... }:
          {
            programs.steam = {
              enable = true;
              gamescopeSession.enable = true;
            };
            programs.gamemode.enable = true;
            environment.systemPackages = with pkgs; [
              mangohud
              protonup-qt
              lutris
              bottles
              heroic
              steam-rom-manager
            ];
          }
        )

        # Jovian / Steam Deck UI
        (
          { lib, pkgs, ... }:
          {
            services.inputplumber.package =
              lib.mkForce
                inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.inputplumber;
            jovian = {
              steam = {
                enable = true;
                autoStart = true;
                user = "user";
                desktopSession = "plasma";
              };
              devices.steamdeck.enable = false;
            };
          }
        )

        # Sunshine (game streaming) with CUDA
        (
          { pkgs, ... }:
          {
            services.sunshine = {
              enable = true;
              autoStart = true;
              capSysAdmin = true;
              openFirewall = true;
              package = pkgs.sunshine.override {
                cudaSupport = true;
                cudaPackages = pkgs.cudaPackages;
              };
            };
            services.avahi = {
              enable = true;
              publish = {
                enable = true;
                userServices = true;
              };
            };
            boot.kernelModules = [ "uinput" "uhid" ];
          }
        )

        # Workstation tools
        (
          { pkgs, ... }:
          {
            environment.systemPackages = with pkgs; [
              git
              nixfmt
              jq
              unzip
              iperf3
              unar
              (brave.override {
                commandLineArgs = [
                  "--disable-font-subpixel-positioning"
                  "--enable-features=WebUIDarkMode"
                  "--force-color-profile=srgb"
                  "--enable-font-antialiasing"
                ];
              })
              qemu
            ];
          }
        )

        # SSH
        { services.openssh.enable = true; }

        # Networking (common)
        {
          networking.networkmanager.enable = true;
          networking.firewall.enable = false;
        }

        # Caches
        (
          { ... }:
          {
            nix.settings = {
              substituters = [
                "https://attic.xuyh0120.win/lantian"
                "https://jovian-experiments.cachix.org"
                "https://cmspam.cachix.org"
                "https://lanzaboote.cachix.org"
              ];
              trusted-public-keys = [
                "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
                "jovian-experiments.cachix.org-1:TyDJIG9AdB5uEAHVAVCjXU1qKBZkCIvqj4rDRz5/sfY="
                "cmspam.cachix.org-1:Xd8Ff8s65DuMHtLf+kpSsdBB62gokpj5PQWA74NU++s="
                "lanzaboote.cachix.org-1:Nt9//zGmqkg1k5iu+B3bkj3OmHKjSw9pvf3faffLLNk="
              ];
              trusted-users = [ "root" "@wheel" ];
            };
          }
        )

        # Controllers
        (
          { pkgs, ... }:
          {
            hardware.xone.enable = true;
            environment.systemPackages = with pkgs; [ evdevhook2 ];
          }
        )

        # Mongolian keyboard layout
        (
          { pkgs, ... }:
          {
            services.xserver.xkb.extraLayouts.mnc = {
              description = "Mongolian (Custom)";
              languages = [ "mon" ];
              symbolsFile = pkgs.writeText "mnc-symbols" ''
                default partial alphanumeric_keys
                xkb_symbols "basic" {
                    name[Group1]= "Mongolian (Custom)";
                    include "level3(ralt_switch)"
                };
              '';
            };
          }
        )

        # Boot-to-Windows helper
        (
          { pkgs, ... }:
          {
            systemd.services.reboot-to-windows = {
              description = "Reboot to Windows";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = "${pkgs.systemd}/bin/bootctl set-oneshot auto-windows";
                ExecStopPost = "${pkgs.systemd}/bin/systemctl reboot";
              };
            };
            environment.systemPackages = [
              (pkgs.writeScriptBin "reboot-to-windows" ''
                #!/usr/bin/env bash
                systemctl start reboot-to-windows.service
              '')
            ];
          }
        )

        # Generic user account (no identifying info)
        (
          { ... }:
          {
            users.users.user = {
              isNormalUser = true;
              extraGroups = [ "networkmanager" "wheel" "render" "input" ];
            };
          }
        )

        # System version
        { system.stateVersion = "25.11"; }
      ];

      # Zephyrus also has: touchpad KWin script (Zephyrus-only due to plasma6 guard)
      zephyrusProfileModules = sharedProfileModules ++ [
        (
          { config, pkgs, lib, ... }:
          {
            # The touchpad module installs a KWin script and a systemd user service.
            # We include it so its closure (dbus, gnugrep, kconfig packages) is cached.
            config = lib.mkIf config.services.desktopManager.plasma6.enable {
              systemd.user.services.scroll-factor-listener = {
                description = "Touchpad Scroll Factor Daemon";
                wantedBy = [ "graphical-session.target" ];
                after = [ "graphical-session.target" ];
                script = ''
                  ${pkgs.dbus}/bin/dbus-monitor --session "interface='org.cmspam.ScrollFix'" | \
                  while read -r line; do : ; done
                '';
                serviceConfig = { Restart = "always"; RestartSec = "5"; };
              };
            };
          }
        )
      ];

      gamePCProfileModules = sharedProfileModules;

      # --------------------------------------------------------
      # BBR module - inline the bbr-dev + bbr.nix logic so the
      # CI flake builds the kernel modules against each host's
      # specific kernel without importing from a relative path.
      # --------------------------------------------------------
      bbrModule =
        { config, pkgs, lib, ... }:
        let
          cfg = config.networking.bbr_dev;
          kernel = config.boot.kernelPackages.kernel;
          isClang = kernel.stdenv.cc.isClang or false;

          bbrv1Source = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/torvalds/linux/v6.19/net/ipv4/tcp_bbr.c";
            sha256 = "sha256-XkaGklAiUa2iM84knrXJixVYRpAyadBOBQVQDu/S6Z8=";
          };

          mkBBRVariant =
            { name, patchContent ? "" }:
            kernel.stdenv.mkDerivation {
              pname = "tcp-${name}";
              version = "1.0-dev";
              src = bbrv1Source;
              nativeBuildInputs = kernel.moduleBuildDependencies;
              unpackPhase = ":";
              buildPhase = ''
                cp $src tcp_${name}.c
                sed -i 's/"bbr"/"${name}"/g' tcp_${name}.c
                sed -i 's/struct bbr/struct ${name}/g' tcp_${name}.c
                ${patchContent}
                TCP_H="${kernel.dev}/lib/modules/${kernel.modDirVersion}/source/include/net/tcp.h"
                if ! grep -q "min_tso_segs" "$TCP_H"; then
                  sed -i 's/\.min_tso_segs/\/\/ .min_tso_segs/g' tcp_${name}.c
                fi
                echo "obj-m += tcp_${name}.o" > Makefile
                make_flags=""
                if [ "${if isClang then "1" else "0"}" = "1" ]; then
                  make_flags="LLVM=1 CC=clang"
                fi
                make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
                  M=$(pwd) $make_flags modules
              '';
              installPhase = ''
                mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
                cp tcp_${name}.ko $out/lib/modules/${kernel.modDirVersion}/extra/
              '';
            };

          bbr_classic_mod = mkBBRVariant { name = "bbr_classic"; };
          bbr_turbo = mkBBRVariant {
            name = "bbr_turbo";
            patchContent = ''
              sed -i 's/static const int bbr_cwnd_gain = BBR_UNIT \* 2;/static const int bbr_cwnd_gain = BBR_UNIT * 4;/g' tcp_bbr_turbo.c
              sed -i 's/BBR_UNIT \* 5 \/ 4,/BBR_UNIT * 2,/g' tcp_bbr_turbo.c
              sed -i 's/BBR_UNIT \* 3 \/ 4,/BBR_UNIT * 9 \/ 10,/g' tcp_bbr_turbo.c
            '';
          };
          bbr_hyper = mkBBRVariant {
            name = "bbr_hyper";
            patchContent = ''
              sed -i 's/static const int bbr_cwnd_gain = BBR_UNIT \* 2;/static const int bbr_cwnd_gain = BBR_UNIT * 5;/g' tcp_bbr_hyper.c
              sed -i 's/BBR_UNIT \* 5 \/ 4,/BBR_UNIT * 5 \/ 2,/g' tcp_bbr_hyper.c
              sed -i 's/BBR_UNIT \* 3 \/ 4,/BBR_UNIT,/g' tcp_bbr_hyper.c
              sed -i 's/static const int bbr_high_gain = BBR_UNIT \* 2885 \/ 1000 + 1;/static const int bbr_high_gain = BBR_UNIT * 4;/g' tcp_bbr_hyper.c
              sed -i 's/static const u32 bbr_probe_rtt_mode_ms = 200;/static const u32 bbr_probe_rtt_mode_ms = 50;/g' tcp_bbr_hyper.c
              sed -i 's/static const u32 bbr_rtprop_filter_len_ms = 10 \* MSEC_PER_SEC;/static const u32 bbr_rtprop_filter_len_ms = 30 * MSEC_PER_SEC;/g' tcp_bbr_hyper.c
            '';
          };
          bbr_jp = mkBBRVariant {
            name = "bbr_jp";
            patchContent = ''
              sed -i 's/static const int bbr_cwnd_gain = BBR_UNIT \* 2;/static const int bbr_cwnd_gain = BBR_UNIT * 4;/g' tcp_bbr_jp.c
              sed -i 's/BBR_UNIT \* 5 \/ 4,/BBR_UNIT * 7 \/ 4,/g' tcp_bbr_jp.c
              sed -i 's/BBR_UNIT \* 3 \/ 4,/BBR_UNIT * 4 \/ 5,/g' tcp_bbr_jp.c
              sed -i 's/static const u32 bbr_probe_rtt_mode_ms = 200;/static const u32 bbr_probe_rtt_mode_ms = 100;/g' tcp_bbr_jp.c
              sed -i 's/static const u32 bbr_rtprop_filter_len_ms = 10 \* MSEC_PER_SEC;/static const u32 bbr_rtprop_filter_len_ms = 20 * MSEC_PER_SEC;/g' tcp_bbr_jp.c
              sed -i 's/static const u32 bbr_min_rtt_win_sec = 10;/static const u32 bbr_min_rtt_win_sec = 20;/g' tcp_bbr_jp.c
            '';
          };
          bbr_ultra = mkBBRVariant {
            name = "bbr_ultra";
            patchContent = ''
              sed -i 's/static const int bbr_cwnd_gain = BBR_UNIT \* 2;/static const int bbr_cwnd_gain = BBR_UNIT * 6;/g' tcp_bbr_ultra.c
              sed -i 's/BBR_UNIT \* 5 \/ 4,/BBR_UNIT * 3,/g' tcp_bbr_ultra.c
              sed -i 's/BBR_UNIT \* 3 \/ 4,/BBR_UNIT,/g' tcp_bbr_ultra.c
              sed -i 's/static const int bbr_high_gain = BBR_UNIT \* 2885 \/ 1000 + 1;/static const int bbr_high_gain = BBR_UNIT * 5;/g' tcp_bbr_ultra.c
              sed -i 's/static const u32 bbr_probe_rtt_mode_ms = 200;/static const u32 bbr_probe_rtt_mode_ms = 25;/g' tcp_bbr_ultra.c
              sed -i 's/static const u32 bbr_rtprop_filter_len_ms = 10 \* MSEC_PER_SEC;/static const u32 bbr_rtprop_filter_len_ms = 60 * MSEC_PER_SEC;/g' tcp_bbr_ultra.c
            '';
          };
          bbr_insane = mkBBRVariant {
            name = "bbr_insane";
            patchContent = ''
              sed -i 's/static const int bbr_cwnd_gain = BBR_UNIT \* 2;/static const int bbr_cwnd_gain = BBR_UNIT * 10;/g' tcp_bbr_insane.c
              sed -i 's/BBR_UNIT \* 5 \/ 4,/BBR_UNIT * 4,/g' tcp_bbr_insane.c
              sed -i 's/BBR_UNIT \* 3 \/ 4,/BBR_UNIT * 11 \/ 10,/g' tcp_bbr_insane.c
              sed -i 's/static const int bbr_high_gain = BBR_UNIT \* 2885 \/ 1000 + 1;/static const int bbr_high_gain = BBR_UNIT * 8;/g' tcp_bbr_insane.c
              sed -i 's/static const u32 bbr_probe_rtt_mode_ms = 200;/static const u32 bbr_probe_rtt_mode_ms = 10;/g' tcp_bbr_insane.c
              sed -i 's/static const u32 bbr_rtprop_filter_len_ms = 10 \* MSEC_PER_SEC;/static const u32 bbr_rtprop_filter_len_ms = 120 * MSEC_PER_SEC;/g' tcp_bbr_insane.c
              sed -i 's/static const u32 bbr_startup_cwnd_gain = BBR_UNIT \* 2;/static const u32 bbr_startup_cwnd_gain = BBR_UNIT * 8;/g' tcp_bbr_insane.c
            '';
          };
          bbr_absurd = mkBBRVariant {
            name = "bbr_absurd";
            patchContent = ''
              sed -i 's/static const int bbr_cwnd_gain = BBR_UNIT \* 2;/static const int bbr_cwnd_gain = BBR_UNIT * 20;/g' tcp_bbr_absurd.c
              sed -i 's/BBR_UNIT \* 5 \/ 4,/BBR_UNIT * 5,/g' tcp_bbr_absurd.c
              sed -i 's/BBR_UNIT \* 3 \/ 4,/BBR_UNIT * 5 \/ 4,/g' tcp_bbr_absurd.c
              sed -i 's/static const int bbr_high_gain = BBR_UNIT \* 2885 \/ 1000 + 1;/static const int bbr_high_gain = BBR_UNIT * 12;/g' tcp_bbr_absurd.c
              sed -i 's/static const u32 bbr_probe_rtt_mode_ms = 200;/static const u32 bbr_probe_rtt_mode_ms = 5;/g' tcp_bbr_absurd.c
              sed -i 's/static const u32 bbr_rtprop_filter_len_ms = 10 \* MSEC_PER_SEC;/static const u32 bbr_rtprop_filter_len_ms = 300 * MSEC_PER_SEC;/g' tcp_bbr_absurd.c
              sed -i 's/static const u32 bbr_startup_cwnd_gain = BBR_UNIT \* 2;/static const u32 bbr_startup_cwnd_gain = BBR_UNIT * 12;/g' tcp_bbr_absurd.c
              sed -i 's/static const u32 bbr_cwnd_min_target = 4;/static const u32 bbr_cwnd_min_target = 16;/g' tcp_bbr_absurd.c
            '';
          };

          tcp_brutal = kernel.stdenv.mkDerivation {
            pname = "tcp-brutal";
            version = "1.0-dynamic-sysctl";
            src = pkgs.fetchFromGitHub {
              owner = "apernet";
              repo = "tcp-brutal";
              rev = "master";
              sha256 = "sha256-rx8JgQtelssslJhFAEKq73LsiHGPoML9Gxvw0lsLacI=";
            };
            nativeBuildInputs = kernel.moduleBuildDependencies;
            buildPhase = ''
              sed -i '/^#define MIN_CWND 4$/a\
              static unsigned long default_brutal_rate = 122500000;\
              module_param(default_brutal_rate, ulong, 0644);\
              MODULE_PARM_DESC(default_brutal_rate, "Default send rate in bytes per second");
              ' brutal.c
              sed -i 's/brutal->rate = INIT_PACING_RATE;/brutal->rate = default_brutal_rate > 0 ? default_brutal_rate : INIT_PACING_RATE;/g' brutal.c
              echo "obj-m += tcp_brutal.o" > Makefile
              echo "tcp_brutal-objs := brutal.o" >> Makefile
              make_flags=""
              if [ "${if isClang then "1" else "0"}" = "1" ]; then
                make_flags="LLVM=1 CC=clang"
              fi
              make -C ${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
                M=$(pwd) $make_flags modules
            '';
            installPhase = ''
              mkdir -p $out/lib/modules/${kernel.modDirVersion}/extra
              cp tcp_brutal.ko $out/lib/modules/${kernel.modDirVersion}/extra/
            '';
          };
        in
        {
          options.networking.bbr_dev = {
            enable = lib.mkEnableOption "BBR development modules";
            variants = lib.mkOption {
              type = lib.types.listOf (lib.types.enum [
                "classic" "turbo" "hyper" "jp" "ultra" "insane" "absurd" "brutal"
              ]);
              default = [ "classic" "turbo" "hyper" "jp" "ultra" "insane" "absurd" "brutal" ];
            };
          };

          config = lib.mkIf cfg.enable {
            boot.extraModulePackages =
              lib.optionals (builtins.elem "classic" cfg.variants) [ bbr_classic_mod ]
              ++ lib.optionals (builtins.elem "turbo" cfg.variants) [ bbr_turbo ]
              ++ lib.optionals (builtins.elem "hyper" cfg.variants) [ bbr_hyper ]
              ++ lib.optionals (builtins.elem "jp" cfg.variants) [ bbr_jp ]
              ++ lib.optionals (builtins.elem "ultra" cfg.variants) [ bbr_ultra ]
              ++ lib.optionals (builtins.elem "insane" cfg.variants) [ bbr_insane ]
              ++ lib.optionals (builtins.elem "absurd" cfg.variants) [ bbr_absurd ]
              ++ lib.optionals (builtins.elem "brutal" cfg.variants) [ tcp_brutal ];

            boot.kernelModules =
              lib.optionals (builtins.elem "classic" cfg.variants) [ "tcp_bbr_classic" ]
              ++ lib.optionals (builtins.elem "turbo" cfg.variants) [ "tcp_bbr_turbo" ]
              ++ lib.optionals (builtins.elem "hyper" cfg.variants) [ "tcp_bbr_hyper" ]
              ++ lib.optionals (builtins.elem "jp" cfg.variants) [ "tcp_bbr_jp" ]
              ++ lib.optionals (builtins.elem "ultra" cfg.variants) [ "tcp_bbr_ultra" ]
              ++ lib.optionals (builtins.elem "insane" cfg.variants) [ "tcp_bbr_insane" ]
              ++ lib.optionals (builtins.elem "absurd" cfg.variants) [ "tcp_bbr_absurd" ]
              ++ lib.optionals (builtins.elem "brutal" cfg.variants) [ "tcp_brutal" ];

            networking.bbr_dev.enable = true;
          };
        };

    in
    {
      # --------------------------------------------------------
      # NixOS system configurations - not used for deployment
      # but referenced by the build targets below.
      # --------------------------------------------------------
      nixosConfigurations = {
        zephyrus = mkSystem zephyrusModules;
        gamepc = mkSystem gamePCModules;
      };

      # --------------------------------------------------------
      # Explicit build targets - what GitHub Actions will build.
      # Building .#zephyrus-system and .#gamepc-system forces
      # the full closure (kernel + modules + all packages) to
      # be evaluated and pushed to Cachix.
      # --------------------------------------------------------
      packages.${system} = {
        zephyrus-system =
          self.nixosConfigurations.zephyrus.config.system.build.toplevel;

        gamepc-system =
          self.nixosConfigurations.gamepc.config.system.build.toplevel;

        # Convenience: build both at once via `nix build .#all`
        all = nixpkgs.legacyPackages.${system}.symlinkJoin {
          name = "all-systems";
          paths = [
            self.packages.${system}.zephyrus-system
            self.packages.${system}.gamepc-system
          ];
        };
      };

      # Default build target
      defaultPackage.${system} = self.packages.${system}.all;
    };
}
