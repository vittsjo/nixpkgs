{ stdenv, lib, writeScript, buildFHSUserEnv, steam
, steam-runtime-wrapped, steam-runtime-wrapped-i686 ? null
, withJava ? false
, withPrimus ? false
, extraPkgs ? pkgs: [ ] # extra packages to add to targetPkgs
, nativeOnly ? false
, runtimeOnly ? false
}:

let
  commonTargetPkgs = pkgs: with pkgs;
    let
      tzdir = "${pkgs.tzdata}/share/zoneinfo";
      # I'm not sure if this is the best way to add things like this
      # to an FHSUserEnv
      etc-zoneinfo = pkgs.runCommand "zoneinfo" {} ''
        mkdir -p $out/etc
        ln -s ${tzdir} $out/etc/zoneinfo
        ln -s ${tzdir}/UTC $out/etc/localtime
      '';
    in [
      steamPackages.steam-fonts
      # Errors in output without those
      pciutils
      python2
      # Games' dependencies
      xlibs.xrandr
      which
      # Needed by gdialog, including in the steam-runtime
      perl
      # Open URLs
      xdg_utils
      # Zoneinfo
      etc-zoneinfo
      iana-etc
    ] ++ lib.optional withJava jdk
      ++ lib.optional withPrimus primus
      ++ extraPkgs pkgs;

  ldPath = map (x: "/steamrt/${steam-runtime-wrapped.arch}/" + x) steam-runtime-wrapped.libs
           ++ lib.optionals (steam-runtime-wrapped-i686 != null) (map (x: "/steamrt/${steam-runtime-wrapped-i686.arch}/" + x) steam-runtime-wrapped-i686.libs);

  runSh = writeScript "run.sh" ''
    #!${stdenv.shell}
    runtime_paths="${lib.concatStringsSep ":" ldPath}"
    if [ "$1" == "--print-steam-runtime-library-paths" ]; then
      echo "$runtime_paths"
      exit 0
    fi
    export LD_LIBRARY_PATH="$runtime_paths:$LD_LIBRARY_PATH"
    exec "$@"
  '';

in buildFHSUserEnv rec {
  name = "steam";

  targetPkgs = pkgs: with pkgs; [
    steamPackages.steam
    # License agreement
    gnome3.zenity
  ] ++ commonTargetPkgs pkgs;

  multiPkgs = pkgs: with pkgs; [
    # These are required by steam with proper errors
    xlibs.libXcomposite
    xlibs.libXtst
    xlibs.libXrandr
    xlibs.libXext
    xlibs.libX11
    xlibs.libXfixes

    # Needed to properly check for libGL.so.1 in steam-wrapper.sh
    pkgsi686Linux.glxinfo

    # Not formally in runtime but needed by some games
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-ugly
    libdrm
    mono
    xorg.xkeyboardconfig
    xlibs.libpciaccess

    (steamPackages.steam-runtime-wrapped.override {
      inherit nativeOnly runtimeOnly;
    })
  ];

  extraBuildCommands = ''
    mkdir -p steamrt
    ln -s ../lib/steam-runtime steamrt/${steam-runtime-wrapped.arch}
    ${lib.optionalString (steam-runtime-wrapped-i686 != null) ''
      ln -s ../lib32/steam-runtime steamrt/${steam-runtime-wrapped-i686.arch}
    ''}
    ln -s ${runSh} steamrt/run.sh
  '';

  extraInstallCommands = ''
    mkdir -p $out/share/applications
    ln -s ${steam}/share/icons $out/share
    ln -s ${steam}/share/pixmaps $out/share
    sed "s,/usr/bin/steam,$out/bin/steam,g" ${steam}/share/applications/steam.desktop > $out/share/applications/steam.desktop
  '';

  profile = ''
    export STEAM_RUNTIME=/steamrt
    export TZDIR=/etc/zoneinfo
  '';

  runScript = writeScript "steam-wrapper.sh" ''
    #!${stdenv.shell}
    if [ -f /host/etc/NIXOS ]; then   # Check only useful on NixOS
      glxinfo >/dev/null 2>&1
      # If there was an error running glxinfo, we know something is wrong with the configuration
      if [ $? -ne 0 ]; then
        cat <<EOF > /dev/stderr
    **
    WARNING: Steam is not set up. Add the following options to /etc/nixos/configuration.nix
    and then run \`sudo nixos-rebuild switch\`:
    { 
      hardware.opengl.driSupport32Bit = true;
      hardware.pulseaudio.support32Bit = true;
    }
    **
    EOF
      fi
    fi
    steam
  '';

  passthru.run = buildFHSUserEnv {
    name = "steam-run";

    targetPkgs = commonTargetPkgs;
    inherit multiPkgs extraBuildCommands;

    runScript = writeScript "steam-run" ''
      #!${stdenv.shell}
      run="$1"
      if [ "$run" = "" ]; then
        echo "Usage: steam-run command-to-run args..." >&2
        exit 1
      fi
      shift
      export LD_LIBRARY_PATH=${lib.concatStringsSep ":" ldPath}:$LD_LIBRARY_PATH
      exec "$run" "$@"
    '';
  };
}
