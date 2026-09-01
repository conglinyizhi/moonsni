# moonbit-sni

**System tray icons for MoonBit on Linux** — a pure MoonBit implementation of the
freedesktop [StatusNotifierItem](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/)
(SNI) specification, built on [moonbit-dbus](https://github.com/conglinyizhi/moonbit-dbus).

No `libappindicator`, no Qt, no GTK. The D-Bus protocol and the SNI service are
both written in MoonBit.

## What it does

Registers your program as a tray item with the desktop's status notifier host
(KDE Plasma, XFCE, Cinnamon, LXQt, GNOME with an extension) and serves the
property queries the host makes — so your icon shows up in the system tray.

## Install

```
moon add clyzhi/moonbit-sni
```

`moon.pkg`:

```
import {
  "clyzhi/moonbit-sni/src" @sni,
}
supported_targets = "+native"
```

## Quick start

Menu items are registered like routes — a key, a title, and a handler. You get a
handle back that lets you change that item at any time.

```
fn main {
  let cfg = @sni.default_tray_config(
    "my-app",                 // Id
    "My Application",         // Title
    "applications-system",    // IconName from the freedesktop icon theme
  )
  let t = @sni.tray(cfg)

  let count = Array::make(1, 0)
  t.on("hello", "Hello", fn(item) {
    count[0] = count[0] + 1
    item.set_title("Clicked \{count[0]} times")   // desktop refreshes automatically
  }) |> ignore

  t.on("quit", "Quit", fn(_item) {
    // do something
  }) |> ignore

  t.run()   // blocks
}
```

The handle is available in two places — as the return value of `on(...)` and as
the argument passed to the handler — so you can update an item from inside its
own callback or from anywhere else:

```
let hello = t.on("hello", "Hello", fn(item) { ... })

hello.set_title("New title")   // later, from anywhere
hello.set_enabled(false)
hello.set_visible(true)
```

## Menu building blocks

Beyond plain actions, the menu supports separators, checkboxes, and submenus of
any depth:

```
t.on("hello", "Hello", fn(item) { ... }) |> ignore   // action

t.separator()                                        // divider

t.checkbox("dark", "Dark mode", false, fn(item) {    // checkbox
  // checked is already toggled; item.checked() reflects it
}) |> ignore

let tools = t.submenu("tools", "Tools")              // submenu -> builder
tools.on("tool-0", "Tool #0", fn(item) { ... }) |> ignore
tools.checkbox("verbose", "Verbose", false, fn(_) { }) |> ignore
tools.separator()

let advanced = tools.submenu("advanced", "Advanced") // nested submenu
advanced.on("adv-0", "Advanced #0", fn(item) { ... }) |> ignore

let deeper = advanced.submenu("deeper", "Even deeper")  // grandchild
deeper.on("bottom", "You found the bottom", fn(_) { }) |> ignore
```

- `.separator()` renders a divider
- `.checkbox(key, title, checked, handler)` auto-toggles `checked` on click
- `.submenu(key, title)` returns a builder with the same `on/checkbox/separator/submenu`
  methods, so nesting is unlimited
- The submenu builder itself has `.handle()` to get a handle for the container

Every handle has `set_title`, `set_enabled`, `set_visible`, `set_checked`,
`toggle`, `title`, `checked`, `key`.

## Internationalization (i18n)

Menus are internationalization-friendly by design. Register items with a
**description key** instead of a literal label, then apply a translation table
at runtime — without rebuilding the menu:

```
let zh : Map[String, String] = { "menu.file": "文件", "menu.new": "新建文档", ... }
let en : Map[String, String] = { "menu.file": "File", "menu.new": "New document", ... }

let t = @sni.tray(cfg)
t.submenu("menu.file", en["menu.file"])
  |> ignore
t.on("menu.new", en["menu.new"], fn(item) { ... }) |> ignore

t.apply_translations(en)   // initial language
// later, to switch at runtime:
t.apply_translations(zh)
```

`apply_translations` walks the whole menu tree and replaces each item's title by
its key. Every item's `key` is preserved, so any mapped label can be swapped.
Unmapped keys keep their current title.

This fits the gettext pattern: use `menu.hello`-style keys in code, resolve
labels from a catalog. Verify with the `tray-demo` example — a `Language`
submenu switches the entire menu between Chinese and English at runtime.

When a handler changes an item, the menu is marked dirty and a
`com.canonical.dbusmenu.LayoutUpdated` signal is emitted, so the desktop
re-reads the layout.

### Handlers must return quickly

`run()` serves requests in a single blocking loop, and handlers run **inside**
that loop. A slow handler blocks everything else — property queries, other menu
clicks. Keep handlers short and push real work elsewhere:

```
t.on("scan", "Scan document", fn(item) {
  item.set_title("Scanning…")
  // spawn a detached process instead of doing the work here
}) |> ignore
```

## How it works

```
run_tray()
  ├─ connect to the session bus + SASL auth        (moonbit-dbus)
  ├─ Hello handshake
  ├─ RequestName  org.kde.StatusNotifierItem-<pid>-1
  ├─ RegisterStatusNotifierItem  → status notifier watcher
  └─ serve loop
       ├─ org.freedesktop.DBus.Properties.Get     → single property
       └─ org.freedesktop.DBus.Properties.GetAll  → a{sv} of all properties
```

Properties served: `Category`, `Id`, `Title`, `Status`, `IconName`,
`Menu` (object path), `ItemIsMenu`.

> **Note:** `Menu` must be present in the `GetAll` reply, otherwise the desktop
> does not know the item has a menu and right-clicking does nothing. This one
> cost us an afternoon.

Menu interface (`com.canonical.dbusmenu` at `/MenuBar`):

| Method | Behaviour |
|---|---|
| `GetLayout` | Returns the menu tree as `(u(ia{sv}av))` |
| `Event` | `clicked` events are routed to the handler registered for that id |
| `AboutToShow` | Returns `false` (no dynamic rebuild needed) |

## API

| Function | Purpose |
|---|---|
| `tray(cfg)` | Create a tray |
| `Tray::on(key, title, handler)` | Register a menu item, returns a handle |
| `Tray::item(key)` | Look up a handle by key |
| `Tray::run()` | Register with the desktop and serve (blocks) |
| `ItemHandle::set_title(s)` | Change the label; desktop refreshes |
| `ItemHandle::set_enabled(b)` | Enable / disable the item |
| `ItemHandle::set_visible(b)` | Show / hide the item |
| `ItemHandle::set_checked(b)` | Set the checkbox state |
| `ItemHandle::toggle()` | Flip the checkbox state |
| `ItemHandle::title()` / `checked()` / `key()` | Read current state |
| `Menu::separator()` | Add a divider |
| `Menu::checkbox(key, title, checked, h)` | Add a checkbox |
| `Menu::submenu(key, title)` | Add a submenu (returns a builder) |
| `SubMenu::on/checkbox/separator/submenu` | Nest further |
| `run_tray(cfg)` | Shortcut for a tray with no menu |

## Configuration

```
pub struct TrayConfig {
  id : String          // application id, e.g. "my-app"
  title : String       // human readable title
  icon_name : String   // freedesktop icon theme name
  status : String      // "Active" | "Passive" | "NeedsAttention"
  category : String    // "ApplicationStatus" | "Communications" | ...
}
```

`default_tray_config(id, title, icon_name)` fills `status = "Active"` and
`category = "ApplicationStatus"`.

Pick `icon_name` from your icon theme — `applications-system`, `dialog-information`,
`media-record`, etc. Run `ls /usr/share/icons/breeze/` (or your theme) to browse.

## Verify it works

With the demo running:

```
# should list org.kde.StatusNotifierItem-<pid>-1
busctl --user list | grep StatusNotifierItem

# should return your properties
busctl --user call org.kde.StatusNotifierItem-<pid>-1 \
  /StatusNotifierItem org.freedesktop.DBus.Properties \
  GetAll s org.kde.StatusNotifierItem
```

## Example

`cmd/tray-demo` is a minimal runnable tray:

```
moon build --target native
./_build/native/debug/build/cmd/tray-demo/tray-demo.exe
```

## Status & limitations

Works today:

- Registering a tray item and keeping it alive
- Serving `Get` / `GetAll` for all properties above
- Right-click context menu with click routing and live title updates
- Verified on KDE Plasma 6 (Wayland)

Not implemented yet:

- Radio groups / toggle-only-radio behavior
- Left-click activation (`Activate`, `SecondaryActivate`, `Scroll`)
- `IconPixmap` (raw pixel icons), `ToolTip`, `AttentionIconName`
- `NewIcon` / `NewStatus` signals
- Removing menu items after registration

## License

Apache-2.0
