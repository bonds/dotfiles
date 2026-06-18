{
  DisableTelemetry = true;
  DisableFirefoxStudies = true;
  DisableAppUpdate = true;
  ManualAppUpdateOnly = true;
  DisablePocket = true;
  DisableFirefoxAccounts = false;
  DisableAccounts = false;
  DisableFirefoxScreenshots = true;
  OverrideFirstRunPage = "";
  OverridePostUpdatePage = "";
  DontCheckDefaultBrowser = true;
  DisplayBookmarksToolbar = "never";

  EnableTrackingProtection = {
    Value = true;
    Locked = true;
    Cryptomining = true;
    Fingerprinting = true;
  };

  SearchEngines = {
    Default = "DuckDuckGo";
  };

  Preferences = {
    "signon.rememberSignons" = {
      Value = false;
      Status = "locked";
    };
    "browser.contentblocking.category" = {
      Value = "strict";
      Status = "locked";
    };
    "network.trr.mode" = {
      Value = 5;
      Status = "locked";
    };
    "network.trr.uri" = {
      Value = "https://mozilla.cloudflare-dns.com/dns-query";
      Status = "locked";
    };
    "network.dns.disableIPv6" = {
      Value = true;
      Status = "locked";
    };
    "network.dns.disablePrefetch" = {
      Value = true;
      Status = "locked";
    };
    "network.http.speculative-parallel-limit" = {
      Value = 0;
      Status = "locked";
    };
    "network.prefetch-next" = {
      Value = false;
      Status = "locked";
    };
    "network.http.http3.enable" = {
      Value = false;
      Status = "locked";
    };
    "privacy.trackingprotection.enabled" = {
      Value = true;
      Status = "locked";
    };
    "privacy.fingerprintingProtection" = {
      Value = true;
      Status = "locked";
    };
    "privacy.query_stripping.enabled" = {
      Value = true;
      Status = "locked";
    };
    "privacy.bounceTrackingProtection.mode" = {
      Value = 1;
      Status = "locked";
    };
    "media.autoplay.default" = {
      Value = 5;
      Status = "locked";
    };
    "zen.view.experimental-rounded-view" = {
      Value = false;
    };
    "zen.view.compact.hide-toolbar" = {
      Value = true;
    };
    "zen.view.compact.should-enable-at-startup" = {
      Value = true;
    };
    "zen.view.sidebar-expanded" = {
      Value = false;
    };
    "zen.workspaces.force-container-workspace" = {
      Value = true;
    };
  };

  ExtensionSettings = {
    "*" = {
      installation_mode = "blocked";
    };
    "uBlock0@raymondhill.net" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
      installation_mode = "force_installed";
    };
    "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
      installation_mode = "force_installed";
    };
    "addon@darkreader.org" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
      installation_mode = "force_installed";
    };
    "sponsorBlocker@ajay.app" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
      installation_mode = "force_installed";
    };
    "{531906d3-e22f-4a6c-a102-8057b88a1a63}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/singlefile/latest.xpi";
      installation_mode = "force_installed";
    };
    "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/vimium-ff/latest.xpi";
      installation_mode = "force_installed";
    };
    "{1018e4d6-728f-4b20-ad56-37578a4de76b}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/flagfox/latest.xpi";
      installation_mode = "force_installed";
    };
    "{74145f27-f039-47ce-a470-a662b129930a}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi";
      installation_mode = "force_installed";
    };
    "{97d566da-42c5-4ef4-a03b-5a2e5f7cbcb2}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/awesome-rss/latest.xpi";
      installation_mode = "force_installed";
    };
    "leechblockng@proginosko.com" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/leechblock-ng/latest.xpi";
      installation_mode = "force_installed";
    };
    "redirector@einaregilsson.com" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/redirector/latest.xpi";
      installation_mode = "force_installed";
    };
  };
}
