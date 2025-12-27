{
  description = "Wink - C3VOC inventory and transport planning interface";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    ruby-nix.url = "github:inscapist/ruby-nix";
    bundix = {
      url = "github:inscapist/bundix";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, flake-utils, ruby-nix, bundix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        rubyNix = ruby-nix.lib pkgs;

        gemset = import ./gemset.nix;

        # Create the ruby environment
        rubyEnv = rubyNix {
          name = "wink-gems";
          inherit gemset;
          ruby = pkgs.ruby_3_4;
          gemConfig = pkgs.defaultGemConfig // {
            sassc = attrs: {
              buildInputs = [ pkgs.libsass ];
              SASS_LIBSASS_PATH = "${pkgs.libsass}";
            };
          };
        };

        # Base wink derivation with the application
        winkBase = pkgs.stdenv.mkDerivation {
          pname = "wink";
          version = "0.1.0";
          src = ./.;

          buildInputs = [ rubyEnv.env ];

          dontBuild = true;

          installPhase = ''
            runHook preInstall

            mkdir -p $out/share/wink
            cp -r . $out/share/wink
            rm -rf $out/share/wink/.git

            runHook postInstall
          '';

          passthru = {
            inherit rubyEnv;
          };

          meta = with pkgs.lib; {
            description = "C3VOC inventory and transport planning interface";
            homepage = "https://github.com/voc/wink";
            license = licenses.mit;
            platforms = platforms.unix;
          };
        };

        # Helper to create wrapper scripts
        mkWinkWrapper = name: command: pkgs.writeShellScriptBin name ''
          export PATH="${rubyEnv.env}/bin:$PATH"
          export RAILS_ENV="''${RAILS_ENV:-production}"

          # Set up writable working directory
          WINK_STATE_DIR="''${WINK_STATE_DIR:-/var/lib/wink}"
          mkdir -p "$WINK_STATE_DIR"

          # Copy files that Rails uses to detect root (can't be symlinks due to realpath)
          [ -e "$WINK_STATE_DIR/config.ru" ] || cp "${winkBase}/share/wink/config.ru" "$WINK_STATE_DIR/config.ru"
          [ -e "$WINK_STATE_DIR/Gemfile" ] || cp "${winkBase}/share/wink/Gemfile" "$WINK_STATE_DIR/Gemfile"
          [ -e "$WINK_STATE_DIR/Gemfile.lock" ] || cp "${winkBase}/share/wink/Gemfile.lock" "$WINK_STATE_DIR/Gemfile.lock"
          [ -e "$WINK_STATE_DIR/Rakefile" ] || cp "${winkBase}/share/wink/Rakefile" "$WINK_STATE_DIR/Rakefile"

          # Symlink directories that can remain read-only
          for item in app lib public vendor; do
            [ -e "$WINK_STATE_DIR/$item" ] || ln -sf "${winkBase}/share/wink/$item" "$WINK_STATE_DIR/$item"
          done

          # Copy bin directory (scripts reference Rails.root)
          if [ ! -d "$WINK_STATE_DIR/bin" ]; then
            cp -r "${winkBase}/share/wink/bin" "$WINK_STATE_DIR/bin"
            chmod -R u+w "$WINK_STATE_DIR/bin"
          fi

          # Create writable directories
          mkdir -p "$WINK_STATE_DIR"/{tmp,log,storage,tmp/pids,tmp/cache,tmp/sockets}

          # Set up db directory - symlink schema/migrations from store, but allow writable db files
          if [ ! -d "$WINK_STATE_DIR/db" ]; then
            mkdir -p "$WINK_STATE_DIR/db"
            ln -sf "${winkBase}/share/wink/db/migrate" "$WINK_STATE_DIR/db/migrate"
            ln -sf "${winkBase}/share/wink/db/schema.rb" "$WINK_STATE_DIR/db/schema.rb"
            ln -sf "${winkBase}/share/wink/db/seeds.rb" "$WINK_STATE_DIR/db/seeds.rb"
            for f in "${winkBase}/share/wink/db"/*_schema.rb; do
              [ -f "$f" ] && ln -sf "$f" "$WINK_STATE_DIR/db/$(basename "$f")"
            done
          fi

          # Copy config dir structure and symlink files
          if [ ! -d "$WINK_STATE_DIR/config" ]; then
            cp -r "${winkBase}/share/wink/config" "$WINK_STATE_DIR/config"
            chmod -R u+w "$WINK_STATE_DIR/config"
          fi

          # Override with custom config if WINK_CONFIG_DIR is set
          if [ -n "''${WINK_CONFIG_DIR:-}" ] && [ -d "$WINK_CONFIG_DIR" ]; then
            for cfg in "$WINK_CONFIG_DIR"/*.yml; do
              [ -f "$cfg" ] || continue
              base=$(basename "$cfg")
              cp "$cfg" "$WINK_STATE_DIR/config/$base"
            done
          fi

          cd "$WINK_STATE_DIR"
          exec bundle exec ${command} "$@"
        '';

      in
      {
        packages = {
          default = winkBase;

          wink-server = mkWinkWrapper "wink-server" "rails server";
          wink-console = mkWinkWrapper "wink-console" "rails console";
          wink-rake = mkWinkWrapper "wink-rake" "rake";
        };

        # Development shell for local development
        devShells.default = pkgs.mkShell {
          buildInputs = [
            rubyEnv.env
            rubyEnv.ruby
            pkgs.pkg-config
            pkgs.sqlite
            pkgs.libffi
            pkgs.zlib
            pkgs.libyaml
            pkgs.openssl
            pkgs.libsass
            pkgs.nodejs
            pkgs.git
          ] ++ pkgs.lib.optional (pkgs.stdenv.isDarwin) pkgs.darwin.apple_sdk.frameworks.CoreServices;

          shellHook = ''
            echo "Wink development shell"
            echo "Run 'nix run github:inscapist/bundix -- -l' to update gemset.nix"
          '';
        };
      });
}
