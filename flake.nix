{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    foundrix = {
      url = "git+https://codeberg.org/xdevs23/foundrix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The assistant's source, built into the service package by assistant.nix.
    # Not a flake input in the flake sense: the repository's own flake is a
    # development shell only, so the source is taken raw and built here.
    # Pinned in the URL, not only in flake.lock, so the revision both hosts
    # run is explicit here; updating the bot means moving this rev (and the
    # framework's beside it) and committing.
    assistant-src = {
      url = "git+https://github.com/halogenOS/xos-assistant?ref=main&rev=7cce113d656b7536dc1e90195c601247ed9e5e48";
      flake = false;
    };
    # The ledger framework the assistant's workspace names by a relative
    # path one directory above its own root (the assistant's decision 0004:
    # the framework has no public home of its own yet, so the two ship as
    # sibling checkouts). assistant.nix composes the two sources into that
    # layout before building.
    agent-ledger-src = {
      url = "git+https://github.com/xdevs23/ronna-core?ref=main&rev=0e2454bc2aefa55579188080819e5605676786da";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      foundrix,
      ...
    }@flakeArgs:
    let
      lib = nixpkgs.lib;
      foundrixLib = foundrix.lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
    in
    foundrix.nixosModules.pluggedInTo flakeArgs rec {
      nixosConfigurations = {
        "nixos-headless@int" = lib.nixosSystem {
          specialArgs = self.nixosModules.foundrixSpecialArgs;
          modules = [
            ./configuration.nix
            ./environments/int.nix
          ];
        };
        "nixos-headless@prod" = lib.nixosSystem {
          specialArgs = self.nixosModules.foundrixSpecialArgs;
          modules = [
            ./configuration.nix
            ./environments/prod.nix
          ];
        };
      }
      // foundrixLib.deviceFramework.mkDeviceSpecificConfigurations {
        xos-assistant-int = {
          nixosConfiguration = nixosConfigurations."nixos-headless@int";
          deviceConfiguration = ./devices/hetzner;
          platformModule = foundrix.nixosModules.hardware.platform.x86_64;
        };
        xos-assistant-prod = {
          nixosConfiguration = nixosConfigurations."nixos-headless@prod";
          deviceConfiguration = ./devices/hetzner;
          platformModule = foundrix.nixosModules.hardware.platform.x86_64;
        };
      };
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
