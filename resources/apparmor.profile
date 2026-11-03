# SPDX-License-Identifier: GPL-3.0-only
#
# AppArmor profile for Ubuntu 24.04+, where
# kernel.apparmor_restrict_unprivileged_userns=1 blocks Chromium's user-namespace
# sandbox. Install with `install.sh --apparmor` (it substitutes the AppImage
# path), or manually replace @APPIMAGE_PATH@ and copy to
# /etc/apparmor.d/wire-desktop.
#
# This grants the AppImage permission to create a user namespace; it does not
# disable Chromium's sandbox.

abi <abi/4.0>,
include <tunables/global>

profile wire-desktop @APPIMAGE_PATH@ flags=(unconfined) {
  userns,

  include if exists <local/wire-desktop>
}
