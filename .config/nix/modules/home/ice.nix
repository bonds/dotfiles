# Ice menu bar manager settings for accismus.
#
# Behavioral settings only — icon layout (MenuBarAppearanceConfigurationV2)
# is managed by Ice at runtime and changes as apps install/uninstall.
#
# Defaults read from: com.jordanbaird.Ice (~/Library/Preferences)
# Docs: https://github.com/jordanbaird/Ice
{...}: {
  targets.darwin.defaults = {
    "com.jordanbaird.Ice" = {
      # --- Ice Bar ---
      UseIceBar = true; # show hidden icons in a secondary bar below the menu bar
      IceBarLocation = 0; # 0 = below menu bar

      # --- When to reveal hidden icons ---
      ShowOnClick = true; # click the chevron to show
      ShowOnHover = false; # don't show on hover (too eager)
      ShowOnHoverDelay = 0.2;
      ShowOnScroll = true; # scroll/swipe over menu bar to reveal

      # --- Auto-rehide ---
      AutoRehide = true; # rehide after interacting
      RehideStrategy = 0; # 0 = timer-based
      RehideInterval = 15; # seconds before auto-rehide
      TempShowInterval = 15; # seconds for temporary show

      # --- Sections ---
      EnableAlwaysHiddenSection = true; # enable the always-hidden section
      CanToggleAlwaysHiddenSection = true; # allow toggling it via shortcut
      ShowSectionDividers = false; # no visual dividers between sections

      # --- Appearance ---
      HideApplicationMenus = true; # hide app menus when they overlap items
      ShowIceIcon = true; # show the Ice icon in the menu bar
      CustomIceIconIsTemplate = false;
      ItemSpacingOffset = 0;

      # --- Drag behavior ---
      ShowAllSectionsOnUserDrag = true; # show all sections when ⌘-dragging

      # --- Auto-update (disabled — nix manages the app) ---
      SUAutomaticallyUpdate = false;
      SUEnableAutomaticChecks = false;
      SUSendProfileInfo = false;
    };
  };
}
