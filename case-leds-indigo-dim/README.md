# case-leds-indigo-dim

Sets all internal case RGB devices to indigo (#4B0082) at 10 percent
brightness (RGB hex `08000D`) at boot and after resume, using OpenRGB.
USB peripherals (keyboard, mouse) are deliberately left untouched.

## WHY

Stock RGB controllers default to bright rainbow effects. The motherboard
Aura controller keeps a hardware static color across reboots, but DRAM
and GPU controllers revert to their vendor default effect on every power
loss, so a boot-time and resume-time reapply service is required.

## WHAT (hardware this targets)

| Device | Controller | OpenRGB mode used | Persists on its own? |
|--------|-----------|-------------------|----------------------|
| ASUS TUF GAMING B550-PLUS WIFI II | ASUS Aura USB (0b05:1939), 2 onboard zones + 2 RGB headers + 2 ARGB headers | `static` | yes (Aura hardware) |
| Corsair Dominator Platinum DRAM (x2) | SMBus 0x5A/0x5B on i2c-1 | `direct` | no |
| Gigabyte GeForce RTX 4070 Ti Eagle OC | RGB Fusion 2 over GPU I2C 0x71 | `direct` | no |

Device selection is by name pattern. OpenRGB 1.0 prints one
`<index>: <name>` line per device for `--list-devices` and reports no
device type, so the `motherboard_match`, `dram_match`, and `gpu_match`
globs in `/etc/case-leds-indigo-dim.conf` classify each device. The
indices handed to `openrgb` come from the same listing the patterns were
matched against, so unplugging a peripheral renumbers the list without
moving a device under a pattern that does not name it.

A controller whose driver loads after this service, such as the GPU
controller behind the NVIDIA i2c adapter, is absent from the listing and
keeps its vendor default until the resume run or a manual restart. Only
the motherboard controller is required; its absence after
`detect_retries` listings fails the unit.

## Monitors (not controllable from software on Linux)

- **Samsung Odyssey G7 (LC27G7xT)**: the bright ring is "Infinity Core
  Lighting". Samsung exposes no DDC/CI or USB control for it; it is
  OSD-only. Disable via the monitor joystick: menu -> **System ->
  Core Lighting -> Off** (newer firmware moves it under **Game**).
  There is no dim option, only off or effect selection.
- **LG UltraGear 34GN850 (GSM774B)**: has no RGB lighting hardware; LG
  dropped Sphere Lighting from the GN series. The only light is the
  small power LED, which can be disabled in its OSD under
  **General -> Power LED**.

## HOW

```sh
# Build and install
makepkg -si

# Enable at boot and after resume
sudo systemctl enable --now case-leds-indigo-dim.service
```

Change the color or modes in `/etc/case-leds-indigo-dim.conf` (kept as a
pacman backup file), then re-run:

```sh
sudo systemctl restart case-leds-indigo-dim.service
```

Set `led_color=000000` to turn the internal LEDs fully off instead of
dim indigo. The motherboard controller also accepts `motherboard_mode=off`.

Confirm the names the patterns must match before editing them:

```sh
openrgb --noautoconnect --list-devices
```

## Boot cost

Each `openrgb` invocation costs about 4.5 seconds on this hardware, so a
successful run is one listing plus one apply, near 9 seconds. The unit
sets `TimeoutStartSec=45` because systemd leaves the start timeout at
infinity for `Type=oneshot`: without it, the script's own retry budget
decides how long `multi-user.target` waits.

## Rollback

```sh
sudo systemctl disable --now case-leds-indigo-dim.service
sudo pacman -R case-leds-indigo-dim
```

The DRAM and GPU return to vendor default effects on the next power
cycle. To restore the motherboard from hardware static, set any mode
via `openrgb`.

## Note on the OpenRGB SDK server

`openrgb.service` (the SDK server shipped by the openrgb package) and
oneshot CLI invocations contend for the same SMBus devices. The oneshot
invocation used by case-leds-indigo-dim exits immediately after applying,
so coexistence is fine, but avoid running both at the same instant.
