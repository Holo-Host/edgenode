This contains a list of high level work items left to be done for HolOS. As each of these is refined, these will become specific Github issues.

* Find someone not colourblind to get a little consistency between:
    - The boot loader menu colours (syslinux theme)
    - The OpenRC colours (EINFO\_COLORS environment variable)
    - The installer theme (Rust dialoguer/console crate theme)
  Obviously not super critical, but will definitely add to the polish
* Add a lightweight control for the holoport LEDs
* Add support for static IP addressing
* Add support for Wi-Fi
* Add support for (limited) USB network device support (to support Wi-Fi on holoports)
* Flesh out the support for different models. Nothing too sophisticated initially, but need better support than we have today. For example, in the case of Holoport Plus, using the SSD for container volumes, and better support for at least one flavour of VM for easier testing.
* Container config and autostart from HolOS
* Propogate OS configuration to installed drive. Configuration is somewhat more a set of overrides for discovered detected defaults (for ease of use), but still needs to propagate to the installed drive.
* Security:
    - Disable root password-based login
    - For local interactive tasks (installing, for example), have the installer started by runlevel (selected at boot time) and without a shell.
* Installer:
    - Should be simple menu-based approach with no more than a few screens (using Rust wrappers around `dialog`).
    - Should separate system volume and application volume
    - Should be selected at boot time using OpenRC runlevels, but should also be runnable via ssh
    - Needs better error handling and user feedback
* Fix logo
* Support upgrades -- currently, the only automated way to update a system is to reinstall. It ought to be possible to upgrade without losing any data or state.
