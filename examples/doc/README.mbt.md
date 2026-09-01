# MoonBit SNI — 可编译示例

这些示例会被 `moon check` 真实验证（`mbt check` 块），保证文档跟实际 API 一致。
完整可运行的托盘见 `cmd/tray-demo`。

## 快速开始：托盘图标 + 右键菜单

```mbt check
///|
test "quick start tray" {
  let cfg = @tray.default_tray_config(
    "my-app", // Id
     "My Application", // Title
     "applications-system", // IconName from the freedesktop icon theme
  )
  let t = @tray.tray(cfg)

  // 注册菜单项：key / 标题 / 回调。返回句柄，可随时改标题等。
  let _handle = t.on("hello", "Hello", fn(item) {
    item.set_title("Clicked " + item.key())
  })
  let _quit = t.on("quit", "Quit", fn(_item) {  })
}
```

句柄在「注册时返回值」和「回调参数」两处都有，可随时更新：

```mbt check
///|
test "handle is live and updatable" {
  let t = @tray.tray(
    @tray.default_tray_config("app", "App", "applications-system"),
  )
  let hello = t.on("hello", "Hello", fn(item) { item.set_title("Clicked") })
  hello.set_title("New title") // 从别处也能改
  hello.set_enabled(false)
  hello.set_visible(true)
  let found = t.item("hello")
  if found is Some(it) {
    assert_eq(it.title(), "New title")
  } else {
    fail("hello item not found")
  }
}
```

## 菜单构建基元

```mbt check
///|
test "menu building blocks" {
  let t = @tray.tray(
    @tray.default_tray_config("app", "App", "applications-system"),
  )

  t.on("hello", "Hello", fn(_item) {  }) |> ignore
  t.separator()
  t.checkbox("dark", "Dark mode", false, fn(item) {
    // checked 已翻转，item.checked() 反映真实状态
    let _ = item.checked()
  })
  |> ignore

  // 子菜单（可无限嵌套）
  let tools = t.submenu("tools", "Tools")
  let _tool0 = tools.on("tool-0", "Tool #0", fn(_item) {  })
  let advanced = tools.submenu("advanced", "Advanced")
  let _adv0 = advanced.on("adv-0", "Advanced #0", fn(_item) {  })
}
```

## 运行时 i18n 切换

用「描述 key」注册，运行时 `apply_translations` 整体切换，不重建菜单：

```mbt check
///|
test "runtime i18n" {
  let t = @tray.tray(
    @tray.default_tray_config("app", "App", "applications-system"),
  )
  t.on("menu.file", "File", fn(_item) {  }) |> ignore
  t.submenu("menu.language", "Language") |> ignore

  // 初始英文
  let en : Map[String, String] = {
    "menu.file": "File",
    "menu.language": "Language",
  }
  t.apply_translations(en)

  // 运行时切中文
  let zh : Map[String, String] = {
    "menu.file": "文件",
    "menu.language": "语言",
  }
  t.apply_translations(zh)

  let _found = t.item("menu.file")
}
```

## 左键 / 中键 / 滚轮事件

```mbt check
///|
test "pointer & scroll events" {
  let t = @tray.tray(
    @tray.default_tray_config("app", "App", "applications-system"),
  )

  t.on_click(fn(x, y) { let _ = (x, y) }) // 左键 Activate
  t.on_middle_click(fn(x, y) { let _ = (x, y) }) // 中键 SecondaryActivate
  t.on_scroll(fn(delta, orientation) { // 滚轮 Scroll
    let _ = (delta, orientation)
  })
}
```

## 纯菜单模型（不要 D-Bus 也能用）

`@menu` 是纯数据，零 D-Bus 依赖。只想建菜单、不想要托盘时用它：

```mbt check
///|
test "pure menu model, no D-Bus" {
  let m = @menu.Menu::new()
  let h = m.on("qr", "识别二维码", fn(item) {
    item.set_title("识别中…")
  })
  h.set_title("扫描中…")
  let found = m.get("qr")
  if found is Some(it) {
    assert_eq(it.title(), "扫描中…")
  } else {
    fail("not found")
  }
}
```

## 纯协议编解码（用自己的菜单驱动 dbusmenu）

`@dbusmenu` 是纯函数编解码，可接入自定义菜单源：

```mbt check
///|
test "dbusmenu codec is pure" {
  let m = @menu.Menu::new()
  m.on("a", "A", fn(_item) {  }) |> ignore
  // 编码整个菜单树为 dbusmenu 布局
  let bytes = @dbusmenu.encode_layout(m, 1, 0, -1)
  assert_true(bytes.length() > 0)
  // 解析 Event 调用
  let _ev = @dbusmenu.parse_event(bytes)
}
```

## D-Bus 服务端（用 moondbus 的 Server）

```mbt check
///|
test "moondbus server dispatch" {
  // 只验分配逻辑：构造一个 dispatch 并调用（不真正连总线）
  let r = dispatch_ping("com.example", "Ping")
  if r is Some(reply) {
    assert_eq(reply.signature, "v")
  } else {
    fail("expected reply")
  }
}

///|
/// 模拟一个服务分发：Ping 返回 pong，其它不回。
fn dispatch_ping(iface : String, member : String) -> @dbus.Reply? {
  if iface == "com.example" && member == "Ping" {
    Some(@dbus.Reply::make(@dbus.build_variant_string("pong"), "v"))
  } else {
    None
  }
}
```
