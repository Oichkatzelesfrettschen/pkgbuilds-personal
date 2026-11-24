# pkgbuilds-personal agent guide

This public repository holds the owner's own Arch Linux and CachyOS packages that
have no upstream release: workstation configuration (memory and swap policy,
sensors, kernel and module parameters), shell and editor configuration, desktop
ricing, hardware helper tools and the specs that justify them. Recipes that track
an upstream release live in gororoba-pkgbuilds.

## Publication boundary

- Public. No host name, IP address, account identifier, credential location,
  private repository URL, personal email or absolute home path. Hardware models,
  firmware versions and measured parameters are published, because each
  configuration value is justified by them.
- `scripts/scrub-check.sh` runs before every push and in CI.
- Maintainer lines read
  `Oichkatzelesfrettschen <151315375+Oichkatzelesfrettschen@users.noreply.github.com>`.

## Configuration packages

- Each configuration value carries, beside it or in the package's README, the
  measurement or document that justifies it and the observation that would
  falsify it. `docs/SYSTEM.md` records the target hardware.
- A package that replaces an older name declares `provides`, `conflicts` and
  `replaces` for it, so `pacman -Syu` migrates without a manual removal.
- Files under /etc are listed in `backup=()`.

## Landing

Pull request, CI green, merge commit by the owner. Commit subjects read
`component: mechanism`; no AI attribution; emoji-free American English.
Builds and test suites run in CI, not on the workstation.
