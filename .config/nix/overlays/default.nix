# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });

    # https://github.com/shaunsingh/SFMono-Nerd-Font-Ligaturized
    sf-mono-liga-bin = prev.stdenvNoCC.mkDerivation rec {
        pname = "sf-mono-liga-bin";
        version = "dev";
        src = inputs.sf-mono-liga-src;
        dontConfigure = true;
        installPhase = ''
          mkdir -p $out/share/fonts/opentype
          cp -R $src/*.otf $out/share/fonts/opentype/
        '';
    };

    # https://wiki.nixos.org/wiki/GNOME
    gnome = prev.gnome.overrideScope (gnomeFinal: gnomePrev: {
      mutter = gnomePrev.mutter.overrideAttrs (old: {
        src = final.pkgs.fetchFromGitLab  {
          domain = "gitlab.gnome.org";
          owner = "vanvugt";
          repo = "mutter";
          rev = "triple-buffering-v4-46";
          hash = "sha256-C2VfW3ThPEZ37YkX7ejlyumLnWa9oij333d5c4yfZxc=";
        };
      });
    });

    # aseprite  = prev.aseprite.overrideAttrs (oldAttrs: {
    #   postInstall = (oldAttrs.postInstall or "") + ''
    #     substituteInPlace $out/share/applications/aseprite.desktop \
    #       --replace "aseprite %U" "env GDK_SCALE=2 aseprite %U"
    #   '';
    # });

  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}
