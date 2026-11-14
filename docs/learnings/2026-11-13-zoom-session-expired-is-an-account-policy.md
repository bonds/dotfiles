# Zoom's "sign in again to renew your session" is an account policy, not a broken install

**Date:** 2026-11-13

## Symptom

The Zoom desktop app on accismus (7.2.2, 88465) started showing, every few
hours, a prompt along the lines of:

```
Your session has expired. Sign in again to renew your session.
```

Restarting the app, and reinstalling it, changed nothing — because the expiry
is decided on the server, not by anything in the client's state.

## Cause

The wording is Zoom's **SSO re-authentication countdown**, not the generic
session error. Both live in
`/Applications/zoom.us.app/Contents/Resources/en.lproj/Localizable.strings`,
and the strings are the tell:

```
"LN_SSO_Count_Down_Title_273370"            = "Renew session";
"LN_SSO_Count_Down_Message_Days_273370"     = "%1$@ requires that you sign in to Zoom every %2$@.

Your session will expire on %3$@. Sign in again to renew your session.";
"LN_SSO_Count_Down_Admin_273370"            = "Your admin";
"LN_Signed_Out_Security_Policy_41410"       = "You've been signed out for being inactive for %d minutes per your account security policy.";
"LN_Session_Warning_Message_273370"         = "Your session will be automatically signed out in %1$@, following %2$@’s policy.";
```

All of them are driven by account settings the user cannot change (Zoom KB0064901,
"Changing account security settings"):

- **Automatically sign users out after a specified time** — default 90 days.
- **Users need to sign in again after a period of inactivity** — web portal 10–120
  minutes, Zoom client **5–120 minutes**.
- **Prevent automatic sign-out of user devices/appliances** — the opt-out.
- When the account is SSO'd, the identity provider's own sign-in frequency
  (Okta re-authentication, Entra "sign-in frequency") can force the same prompt.

The client-side preference keys that record whether the warnings have already
been shown are `kZMLoginHadShowFiveMinsCountDown`,
`kZMLoginHadShowOneHourCountDown`, `kZMLoginHadShowOneDayCountDown` and
`kZMLoginHadShowSessionWarning` in `~/Library/Preferences/us.zoom.xos.plist`.

## Fix

Read the whole dialog first: if it names an organisation (or says "Your admin")
and an interval, no local fix exists — only the account admin, or the IdP
policy, can lengthen it, and the client inactivity cap of 120 minutes means
"once a week" can only come from the admin/SSO interval.

Only when the prompt is the bare `Your session has expired. Please sign in.`
with no org named is it local. Then the levers are:

- Keychain access for the `Zoom Safe Storage` / `so.zoom.us` items — a denied
  "Zoom wants to use your confidential information" prompt stops the token from
  being refreshed.
- Web portal → Profile → **Sign me out from all devices**, then one fresh
  sign-in.
- Zoom's per-device-type sign-in limit (default two) bumping an older session.

Diagnostic that costs nothing:

```fish
rg -n "Count_Down|session has expired" /Applications/zoom.us.app/Contents/Resources/en.lproj/Localizable.strings
defaults read ~/Library/Preferences/us.zoom.xos.plist | rg -i "countdown|session"
```
