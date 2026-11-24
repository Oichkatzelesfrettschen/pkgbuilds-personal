# custom-fast-temporary-directories

This package keeps large temporary workloads off RAM and the root filesystem
without collapsing `/tmp` and `/var/tmp` into one namespace. The ext4 filesystem
with UUID `f80f3ba8-49f9-46ae-9101-c8638f017a64` mounts at `/srv/fasttmp`.
`/tmp` binds from `/srv/fasttmp/tmp`, while `/var/tmp` binds from
`/srv/fasttmp/var-tmp`.

The split preserves the two interfaces defined by `file-hierarchy(7)`:

- `/tmp` is volatile and is cleared during boot.
- `/var/tmp` survives reboot and ages entries after two days.

Both directories are `root:root`, mode `1777`, on a filesystem mounted with
`nosuid,nodev`. The package omits `noexec` because compilers, package tools, and
test suites legitimately execute temporary files.

## Migration

Build and test the package before changing the host configuration:

```sh
makepkg --cleanbuild --syncdeps --noconfirm
namcap PKGBUILD custom-fast-temporary-directories-*.pkg.tar.zst
```

Inspect the exact legacy entries:

```sh
custom-fast-temporary-directories-migrate-config --check
```

The first installation needs the repository copy of the migration command
because the unowned `/etc/tmpfiles.d/tmp.conf` would otherwise collide with the
package-owned file. Run `--apply`, install the package immediately, and reboot:

```sh
sudo ./custom-fast-temporary-directories-migrate-config --apply
sudo pacman -U ./custom-fast-temporary-directories-1.0.0-1-any.pkg.tar.zst
sudo systemctl reboot
```

`--apply` comments only the exact legacy `/tmp` and `/var/tmp` fstab entries,
archives both `/etc/fstab` and the unowned tmpfiles override, and reserves the
root-owned first-boot migration paths. It validates the candidate fstab before
replacing the original. Each rename is atomic on its own filesystem, while the
complete operation is resumable rather than globally atomic: rerunning
`--apply` completes an interruption after either configuration file or after
creating the recovery directory.

At the first boot, the preparation service moves every existing top-level entry
from the former shared filesystem root into
`/srv/fasttmp/legacy-shared-root`. The archive is mode `0700`, exempt from
automatic cleanup, and remains available for explicit review. It then creates
the separate sticky directories and records a completed layout marker.

## Rename from private-fast-temporary-directories

Through 1.0.0 this package was named `private-fast-temporary-directories`;
`provides`, `conflicts` and `replaces` name the former package. On a host
that already runs the split layout, pacman removes the old package first and
its `post_remove` only runs `systemctl daemon-reload`. systemd keeps the
active `srv-fasttmp.mount`, `tmp.mount` and `var-tmp.mount` while their unit
files are replaced, so `/tmp` and `/var/tmp` stay mounted. `pre_install`
accepts the live split layout with a `complete` marker and skips the
first-install checks. `post_install` starts
`custom-fast-temporary-directories-prepare.service`, which renames
`/srv/fasttmp/.private-fast-temporary-directories-layout` to
`.custom-fast-temporary-directories-layout` and re-asserts the directory
modes. The same adoption runs at boot before `tmp.mount`, so the marker
rename never leaves `tmp.mount` without its preparation service. The former
`private-fast-temporary-directories-prepare.service` stays loaded as a
not-found unit until reboot and is not stopped. The test-environment variables
are now `CUSTOM_FAST_TEMPORARY_DIRECTORIES_*`.

Install with `pacman -U` and answer `y` to the conflict question;
`--noconfirm` aborts it. Run `custom-fast-temporary-directories-verify` after
the install and again after the next boot.

## Verification

After reboot, run:

```sh
sudo custom-fast-temporary-directories-verify
systemctl status srv-fasttmp.mount \
  custom-fast-temporary-directories-prepare.service tmp.mount var-tmp.mount
findmnt -T /tmp
findmnt -T /var/tmp
```

The verifier requires distinct inode identities, the expected bind sources,
mode `1777`, active units, and the effective cleanup policy.

To test reboot persistence, create uniquely named files in both paths, reboot,
and confirm that the `/tmp` file is absent while the `/var/tmp` file remains.

## Recovery

The package does not delete the migration backups or the recovery archive.
If the new topology fails before login, boot the fallback entry, restore the
recorded `/etc/fstab.pre-custom-fast-temporary-directories-*` file (named
`/etc/fstab.pre-private-fast-temporary-directories-*` when the former package
name ran the migration) only when
returning deliberately to the shared-root layout, remove or rename the
package-owned mount units, run `systemctl daemon-reload`, and mount the legacy
entries. Removing the package without restoring fstab selects systemd's tmpfs
`/tmp` and the root filesystem's `/var/tmp`. The shared-root content remains in
`/srv/fasttmp/legacy-shared-root` until an administrator explicitly removes it.
