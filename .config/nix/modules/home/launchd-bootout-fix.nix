{lib, ...}: let
  # ---------------------------------------------------------------------------
  # WHY THIS MODULE EXISTS
  #
  # home-manager's launchd activation (modules/launchd/default.nix) unloads a
  # changed agent with:
  #
  #     /bin/launchctl bootout --wait "gui/501/<label>"
  #
  # `--wait` is a macOS 26 (Tahoe) launchctl option. On macOS 15 the `bootout`
  # subcommand accepts NO options at all (see `launchctl help bootout`), so
  # launchctl parses `--wait` as the <domain-target> and aborts:
  #
  #     Unrecognized target specifier.            (exit 64)
  #     Usage: launchctl bootout <domain-target> [service-path1, ...] | <service-target>
  #
  # The old job therefore stays loaded, and the following
  #
  #     /bin/launchctl bootstrap gui/501 <plist>
  #
  # fails with `Bootstrap failed: 5: Input/output error` — the second half of the
  # error pair, not an independent problem.
  #
  # Note the failure is invisible until an agent's *plist content* changes:
  # processAgent() skips agents whose plist is byte-identical (cmp -s), so only
  # the agents whose store paths moved in a given rebuild ever hit bootout.
  #
  # Upstream fixed this on master by gating the flag on the OS version
  # ([[ "$(sw_vers --productVersion | cut -d. -f 1)" -ge 26 ]] → --wait,
  # else plain `bootout` + `sleep 1`). release-26.05, which we track, still has
  # the unconditional `--wait`.
  #
  # This module replaces ONLY that one activation entry with the release-26.05
  # logic minus the unsupported flag (plus the settle delay master added for
  # exactly the "bootout returns before launchd has dropped the label" race that
  # produces a code-5 bootstrap). Everything else — plist generation, the
  # `LaunchAgents` builder commands, the option surface — still comes from
  # home-manager.
  #
  # DELETE THIS MODULE once release-26.05 carries the fix. Test:
  #   grep -c 'bootout --wait' \
  #     $(nix eval --raw --impure --expr \
  #       '(builtins.getFlake "/Users/scott/.config/nix").inputs.home-manager.outPath')/modules/launchd/default.nix
  # A version-gated `--wait` there means upstream landed it and this can go.
  # ---------------------------------------------------------------------------
  # Faithful copy of home-manager release-26.05's `setupLaunchAgents` block, with
  # bootoutAgent() changed to drop `--wait` and wait for the unload instead.
  setupLaunchAgents = ''
    # Disable errexit to ensure we process all agents even if some fail
    set +e

    # Stop an agent if it's running
    bootoutAgent() {
      local domain="$1"
      local agentName="$2"

      verboseEcho "Stopping agent '$domain/$agentName'..."
      local bootout_output
      if bootout_output=$(run /bin/launchctl bootout "$domain/$agentName" 2>&1); then
        # `bootout` returns once the job is removed from the domain, but launchd
        # can still hold the label for a moment; bootstrapping into that window
        # is the other way to get "Bootstrap failed: 5: Input/output error".
        run sleep 1
      elif [[ "$bootout_output" != *"No such process"* ]]; then
        warnEcho "Failed to stop agent '$domain/$agentName': $bootout_output"
      else
        verboseEcho "Agent '$domain/$agentName' was not running"
      fi
    }

    installAndBootstrapAgent() {
      local srcPath="$1"
      local dstPath="$2"
      local domain="$3"
      local agentName="$4"

      verboseEcho "Installing agent file to $dstPath"
      if ! run install -Dm444 -T "$srcPath" "$dstPath"; then
        errorEcho "Failed to install agent file for '$agentName'"
        return 1
      fi

      verboseEcho "Starting agent '$domain/$agentName'"
      local bootstrap_output
      bootstrap_output=$(run /bin/launchctl bootstrap "$domain" "$dstPath" 2>&1) || {
        if [[ "$bootstrap_output" == *"Bootstrap failed: 5: Input/output error"* ]]; then
          errorEcho "Failed to start agent '$domain/$agentName' with I/O error (code 5)"
          errorEcho "This typically happens when the agent wasn't unloaded before attempting to bootstrap the new agent."
        else
          errorEcho "Failed to start agent '$domain/$agentName' with error: $bootstrap_output"
        fi

        return 1
      }

      verboseEcho "Successfully started agent '$domain/$agentName'"
      return 0
    }

    processAgent() {
      local srcPath="$1"
      local dstDir="$2"
      local domain="$3"

      local agentFile="''${srcPath##*/}"
      local agentName="''${agentFile%.plist}"
      local dstPath="$dstDir/$agentFile"

      # Skip if unchanged
      if cmp -s "$srcPath" "$dstPath"; then
        verboseEcho "Agent '$agentName' is already up-to-date"
        return 0
      fi

      verboseEcho "Processing agent '$agentName'"

      # Stop/Unload agent if it's already running
      if [[ -f "$dstPath" ]]; then
        bootoutAgent "$domain" "$agentName"
      fi

      installAndBootstrapAgent "$srcPath" "$dstPath" "$domain" "$agentName"
      # Note: We continue processing even if this agent fails
      return 0
    }

    removeAgent() {
      local srcPath="$1"
      local dstDir="$2"
      local newDir="$3"
      local domain="$4"

      local agentFile="''${srcPath##*/}"
      local agentName="''${agentFile%.plist}"
      local dstPath="$dstDir/$agentFile"

      if [[ -e "$newDir/$agentFile" ]]; then
        verboseEcho "Agent '$agentName' still exists in new generation, skipping cleanup"
        return 0
      fi

      if [[ ! -e "$dstPath" ]]; then
        verboseEcho "Agent file '$dstPath' already removed"
        return 0
      fi

      if ! cmp -s "$srcPath" "$dstPath"; then
        warnEcho "Skipping deletion of '$dstPath', since its contents have diverged"
        return 0
      fi

      # Stop and remove the agent
      bootoutAgent "$domain" "$agentName"

      verboseEcho "Removing agent file '$dstPath'"
      if run rm -f $VERBOSE_ARG "$dstPath"; then
        verboseEcho "Successfully removed agent file for '$agentName'"
      else
        warnEcho "Failed to remove agent file '$agentName'"
      fi

      return 0
    }

    setupLaunchAgents() {
      local oldDir newDir dstDir domain

      newDir="$(readlink -m "$newGenPath/LaunchAgents")"
      dstDir="$HOME/Library/LaunchAgents"
      domain="gui/$UID"

      if [[ -n "''${oldGenPath:-}" ]]; then
        oldDir="$(readlink -m "$oldGenPath/LaunchAgents")"
        if [[ ! -d "$oldDir" ]]; then
          verboseEcho "No previous LaunchAgents directory found"
          oldDir=""
        fi
      else
        oldDir=""
      fi

      verboseEcho "Setting up LaunchAgents in $dstDir"
      [[ -d "$dstDir" ]] || run mkdir -p "$dstDir"

      verboseEcho "Processing new/updated LaunchAgents..."
      find -L "$newDir" -maxdepth 1 -name '*.plist' -type f | while read -r srcPath; do
        processAgent "$srcPath" "$dstDir" "$domain"
      done

      # Skip cleanup if there's no previous generation
      if [[ -z "$oldDir" || ! -d "$oldDir" ]]; then
        verboseEcho "LaunchAgents setup complete"
        return
      fi

      verboseEcho "Cleaning up removed LaunchAgents..."
      find -L "$oldDir" -maxdepth 1 -name '*.plist' -type f | while read -r srcPath; do
        removeAgent "$srcPath" "$dstDir" "$newDir" "$domain"
      done
    }

    setupLaunchAgents

    # Restore errexit
    set -e
  '';
in {
  home.activation.setupLaunchAgents = lib.mkForce (lib.hm.dag.entryAfter ["writeBoundary"] setupLaunchAgents);
}
