# moonsni

**System tray icons for MoonBit on Linux** — a pure MoonBit implementation of the
freedesktop [StatusNotifierItem](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/)
(SNI) specification, built on [moondbus](https://github.com/conglinyizhi/moondbus).

No `libappindicator`, no Qt, no GTK. The D-Bus protocol and the SNI service are
both written in MoonBit.

The code blocks marked `mbt check` below are **actually compiled and run by
`moon check` / `moon test`**, so the documented API stays true to the code. A
full runnable tray is in `cmd/tray-demo`; extra compiled snippets live in
`examples/doc`.

## Progressive by design

`moonsni` is not a framework you have to adopt wholesale. It is built as
**three independent packages**, so you take only what you need:

| Package | What it gives you | Depends on |
|---|---|---|
| `moonsni/src/menu` | Pure menu **data model** — `Menu`, `ItemHandle`, `SubMenu`, checkboxes, i18n. No D-Bus at all. | nothing |
| `moonsni/src/dbusmenu` | Pure `com.canonical.dbusmenu` **wire codec** — encode a menu tree, parse events. | `menu` + moondbus encoder |
| `moonsni/src/tray` | The full **tray** — connect to the bus, register the item, serve requests. | `menu` + `dbusmenu` + moondbus |

This mirrors Vue's spectrum: use the whole thing for a quick tray, or drop down
a level and use just the menu model, or swap in your own wire layer entirely.

- **Just want a tray?** `@tray.tray(cfg)` + `.on(...)` + `.run()`. One line each.
- **Only need a menu, no D-Bus?** Use `@menu.Menu` on its own — it is pure data.
- **Serving your own menu, want to reuse the codec?** Call `@dbusmenu.encode_layout`.
- **Want a different transport?** Write your own package that feeds `menu` and
  drives `dbusmenu` — `tray` is simply one such wiring.

## Install

```
moon add clyzhi/moonsni
```

For the full tray:

```
import {
  "clyzhi/moonsni/src/tray" @tray,
}
supported_targets = "+native"
```

For just the menu model (no D-Bus dependency pulled in):

```
import {
  "clyzhi/moonsni/src/menu" @menu,
}
```

## Quick start

Menu items are registered like routes — a key, a title, and a handler. You get a
handle back that lets you change that item at any time.

```mbt check
///|
test "quick start — build a tray and register menu items" {
  let cfg = @tray.default_tray_config(
    "my-app",              // Id
    "My Application",      // Title
    "applications-system", // IconName
  )
  let t = @tray.tray(cfg)

  let count = Array::make(1, 0)
  let hello = t.on("hello", "Hello", fn(item) {
    count[0] = count[0] + 1
    item.set_title("Clicked " + count[0].to_string())
  })
  let mut _quit = t.on("quit", "Quit", fn(_item) {  })

  // 句柄可随时改标题/可用/可见
  hello.set_title("New title")
  hello.set_enabled(false)
  hello.set_visible(true)
}
```

The handle is available in two places — as the return value of `on(...)` and as
the argument passed to the handler:

```mbt check
///|
test "handle is live and updatable" {
  let t = @tray.tray(@tray.default_tray_config("app", "App", "applications-system"))
  let hello = t.on("hello", "Hello", fn(item) { item.set_title("Clicked") })
  hello.set_title("New title")    // from anywhere
  hello.set_enabled(false)
  hello.set_visible(true)

  match t.item("hello") {
    Some(it) => assert_eq(it.title(), "New title")
    None => fail("hello item not found")
  }
}
```

## Menu building blocks

Beyond plain actions, the menu supports separators, checkboxes, and submenus of
any depth:

```mbt check
///|
test "menu building blocks" {
  let t = @tray.tray(@tray.default_tray_config("app", "App", "applications-system"))

  t.on("hello", "Hello", fn(_item) {  }) |> ignore
  t.separator()                                        // divider

  t.checkbox("dark", "Dark mode", false, fn(item) {    // checkbox
    // checked is already toggled; item.checked() reflects it
    let _toggled = item.checked()
  }) |> ignore

  let tools = t.submenu("tools", "Tools")              // submenu -> builder
  let _tool0 = tools.on("tool-0", "Tool #0", fn(_item) {  })
  tools.separator()

  let advanced = tools.submenu("advanced", "Advanced") // nested submenu
  let _adv0 = advanced.on("adv-0", "Advanced #0", fn(_item) {  })

  let deeper = advanced.submenu("deeper", "Even deeper")  // grandchild
  let _bottom = deeper.on("bottom", "You found the bottom", fn(_item) {  })
}
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

```mbt check
///|
test "runtime i18n" {
  let t = @tray.tray(@tray.default_tray_config("app", "App", "applications-system"))
  t.on("menu.file", "File", fn(_item) {  }) |> ignore
  t.on("menu.new", "New document", fn(_item) {  }) |> ignore

  // 初始英文
  let en : Map[String, String] = { "menu.file": "File", "menu.new": "New document" }
  t.apply_translations(en)
  match t.item("menu.file") {
    Some(it) => assert_eq(it.title(), "File")
    None => fail("not found")
  }

  // 运行时切中文
  let zh : Map[String, String] = { "menu.file": "文件", "menu.new": "新建文档" }
  t.apply_translations(zh)
  match t.item("menu.file") {
    Some(it) => assert_eq(it.title(), "文件")
    None => fail("not found")
  }
}
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
that loop. A slow handler blocks everything else — keep handlers short and push
real work elsewhere.

## Left / middle / scroll events

```mbt check
///|
test "pointer & scroll events" {
  let t = @tray.tray(@tray.default_tray_config("app", "App", "applications-system"))

  t.on_click(fn(x, y) { let _ = (x, y) })         // left-click  Activate
  t.on_middle_click(fn(x, y) { let _ = (x, y) })  // middle-click SecondaryActivate
  t.on_scroll(fn(delta, orientation) {            // wheel Scroll
    let _ = (delta, orientation)                  // orientation 0=vertical 1=horizontal
  })
}
```

## Use only the menu model (no D-Bus)

`@menu` is pure data — build a menu without any tray or D-Bus:

```mbt check
///|
test "pure menu model, no D-Bus" {
  let m = @menu.Menu::new()
  let h = m.on("qr", "识别二维码", fn(item) { item.set_title("识别中…") })
  h.set_title("扫描中…")

  match m.get("qr") {
    Some(it) => assert_eq(it.title(), "扫描中…")
    None => fail("not found")
  }
}
```

## Use the dbusmenu codec on your own data

`@dbusmenu` is a pure codec — feed it any `@menu.Menu` and get a layout:

```mbt check
///|
test "dbusmenu codec is pure" {
  let m = @menu.Menu::new()
  m.on("a", "A", fn(_item) {  }) |> ignore
  let bytes = @dbusmenu.encode_layout(m, 1, 0, -1)   // whole tree
  assert_true(bytes.length() > 0)
}
```

## Full runnable tray

A complete, runnable `fn main` tray (this one genuinely starts a tray icon on
the desktop — it's not compiled as a test because `run()` blocks forever):

```mbt nocheck
///|
fn main {
  let cfg = @tray.default_tray_config(
    "my-app", "My Application", "applications-system",
  )
  let t = @tray.tray(cfg)
  t.on("hello", "Hello", fn(item) { item.set_title("Clicked") }) |> ignore
  t.run()   // blocks; serves the tray until killed
}
```

## How it works

```
run_tray()
  ├─ connect to the session bus + SASL auth        (moondbus Server)
  ├─ Hello handshake
  ├─ RequestName  org.kde.StatusNotifierItem-<pid>-1
  ├─ RegisterStatusNotifierItem  → status notifier watcher
  └─ serve loop  (moondbus Server::serve)
       ├─ org.freedesktop.DBus.Properties.Get      → single property
       ├─ org.freedesktop.DBus.Properties.GetAll   → a{sv} of all properties
       ├─ com.canonical.dbusmenu.GetLayout/Event/AboutToShow  → menu
       ├─ org.kde.StatusNotifierItem.Activate             → on_click(x, y)
       ├─ org.kde.StatusNotifierItem.SecondaryActivate    → on_middle_click(x, y)
       └─ org.kde.StatusNotifierItem.Scroll               → on_scroll(delta, dir)
```

The serve loop is provided by `moondbus`'s `Server` (a reusable D-Bus service
loop), so any future service — MPRIS player, custom object export — can reuse
it instead of hand-writing `recv` / `parse` / `reply`.

Properties served: `Category`, `Id`, `Title`, `Status`, `IconName`,
`Menu` (object path), `ItemIsMenu`.

> **Note:** `Menu` must be present in the `GetAll` reply, otherwise the desktop
> does not know the item has a menu and right-clicking does nothing. `ItemIsMenu`
> should be `true` so the desktop renders a single flat menu rather than treating
> the item as an activation target.

Menu interface (`com.canonical.dbusmenu` at `/MenuBar`):

| Method | Behaviour |
|---|---|
| `GetLayout` | Returns the menu tree as `(u(ia{sv}av))`. Honours the `parentID` argument so the desktop can fetch a submenu's content independently. |
| `Event` | `clicked` events are routed to the handler registered for that id |
| `AboutToShow` | Returns `false` (no dynamic rebuild needed) |

### Protocol detail notes

Two things cost us debugging time and are worth documenting:

1. **`toggle-type` / `toggle-state` must be present on every item** (an empty
   string / `0` for plain actions and submenus). KDE uses them to distinguish
   item types; without them a submenu can be rendered as the whole parent menu.
2. **`GetLayout` receives a `parentID`** (0 for the root, a submenu's id when the
   desktop wants just that submenu). Reply with the corresponding subtree root,
   not the whole menu every time — otherwise clicking a submenu shows the entire
   parent menu again.

## API

### Tray package (`@tray`)

| Function | Purpose |
|---|---|
| `tray(cfg)` | Create a tray |
| `Tray::on(key, title, handler)` | Register a menu item, returns a handle |
| `Tray::item(key)` | Look up a handle by key |
| `Tray::run()` | Register with the desktop and serve (blocks) |
| `Tray::separator()` | Add a divider |
| `Tray::checkbox(key, title, checked, h)` | Add a checkbox |
| `Tray::submenu(key, title)` | Add a submenu (returns a builder) |
| `Tray::apply_translations(table)` | Switch language |
| `Tray::on_click(fn(x, y))` | Left-click activation (`Activate`) |
| `Tray::on_middle_click(fn(x, y))` | Middle-click (`SecondaryActivate`) |
| `Tray::on_scroll(fn(delta, dir))` | Mouse wheel (`Scroll`), dir 0=vertical 1=horizontal |
| `run_tray(cfg)` | Shortcut for a tray with no menu |

### Menu package (`@menu`)

| Function | Purpose |
|---|---|
| `Menu::new()` | Create an empty menu |
| `Menu::on(key, title, handler)` | Add an action, returns a handle |
| `Menu::checkbox(key, title, checked, h)` | Add a checkbox |
| `Menu::submenu(key, title)` | Add a submenu |
| `Menu::separator()` | Add a divider |
| `Menu::get(key)` | Look up a handle |
| `Menu::dispatch(id)` | Route a click by id |
| `Menu::apply_translations(table)` | Switch language |
| `SubMenu::on/checkbox/separator/submenu` | Nest further |

### Handles

Every handle has `set_title`, `set_enabled`, `set_visible`, `set_checked`,
`toggle`, `title`, `checked`, `key`.

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
./_build/native/debug/build/clyzhi/moonsni/cmd/tray-demo/tray-demo.exe
```

## Status & limitations

Works today:

- Registering a tray item and keeping it alive
- Serving `Get` / `GetAll` for all properties above
- Right-click context menu with click routing and live title updates
- Left / middle / scroll events (`Activate`, `SecondaryActivate`, `Scroll`)
- Submenus of arbitrary depth
- Runtime i18n switching (verified: whole menu switches language live)
- Verified on KDE Plasma 6 (Wayland)

Not implemented yet:

- Radio groups / toggle-only-radio behavior
- `IconPixmap` (raw pixel icons), `ToolTip`, `AttentionIconName`
- `NewIcon` / `NewStatus` signals
- Removing menu items after registration

## Roadmap

- **Windows**: D-Bus has no unix-socket transport on Windows — the reference
  `dbus-daemon` uses TCP loopback (`autolaunch:` / `tcp:host=localhost,port=NNNN`).
  The `menu` and `dbusmenu` packages are already independent of any transport, so
  a future Windows backend only needs to plug in a D-Bus transport layer; the tray
  logic and menu codec are reused as-is. No Windows hardware is available to test
  this yet.

## License

Apache-2.0
