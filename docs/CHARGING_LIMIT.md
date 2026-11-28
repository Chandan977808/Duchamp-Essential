# Charging Limit Control

Charging Limit Control suspends **charger input** through the common Android
power-supply node `/sys/class/power_supply/battery/input_suspend`. It is a
charging-stop feature, not a power-path feature: while input is suspended the
system runs from the adapter if the load allows, or from the battery — unlike
bypass charging, which uses a dedicated kernel power-path node with measured
confirmation. The two features use independent kernel interfaces and can be
enabled together.

## Kernel interface

- `/sys/class/power_supply/battery/input_suspend` — readable/writable boolean.
  `1` suspends charger input; `0` lets the charger feed the battery again.
- `/sys/class/power_supply/battery/capacity` — fuel gauge in percent.

Support is detected from the node's presence. Every write is verified by
readback (write, re-read, compare); an unchanged node is never rewritten, so
opening the page or refreshing telemetry cannot restart vendor bookkeeping.

## Contract

`SET charging.limit 1` enables the saved policy; `0` disables it.
`SET charging.limit_threshold VALUE` selects 80, 85, 90 or 95.

While enabled:

- capacity below the limit → `input_suspend=0` (OEM charging continues),
- capacity at or above the limit → `input_suspend=1` (charger input suspended),
- once suspended, input stays suspended **until the level drops below the
  limit** — exactly as selected, with no release band.

When the feature is disabled, `input_suspend` is written back to `0` at once
so the OEM charger controller owns input again. Selecting a limit while the
switch is off only persists the choice; it never touches hardware.

## Persistence and monitoring

The switch and the limit persist together in daemon state, independent of the
Flutter page, the foreground app, or the app process. Transitions are driven by
power-supply uevents and, because capacity steps do not raise uevents on every
kernel, by a two-second maintenance poll while the limit is enabled. Bounded
retry rate-limiting applies to non-explicit reconciles; a failed write is
reported through `charge_limit_error` rather than presented as success.

## Commands and telemetry

- `SET charging.limit {0|1}`, `SET charging.limit_threshold {80|85|90|95}` —
  live, verified application plus persistence.
- Diagnostics fields: `charge_limit_supported`, `charge_limit_state` (live
  `input_suspend` value, `-1` unsupported), `charge_limit_saved`,
  `charge_limit_threshold`, `charge_limit_error`.

The app stays non-root: requests travel Flutter → host bridge → root daemon,
the same path as every other hardware control.
