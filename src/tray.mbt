///|
/// KDE / freedesktop 系统托盘（StatusNotifierItem）。
///
/// 用法是「路由注册」式的：
///
///   let t = @sni.tray(cfg)
///   t.on("qr", "识别二维码", fn(item) { item.set_title("识别中…") })
///   t.run()
///
/// 注册时拿到的句柄可以随时改这一项的标题 / 可用状态。

const MENU_PATH : String = "/MenuBar"

///|
/// 托盘配置。
pub struct TrayConfig {
  id : String          // 应用 id
  title : String       // 标题
  icon_name : String   // freedesktop 图标主题里的图标名
  status : String      // "Active" / "Passive" / "NeedsAttention"
  category : String    // "ApplicationStatus" 等
}

///|
/// 常用默认值：Active + ApplicationStatus。
pub fn default_tray_config(
  id : String,
  title : String,
  icon_name : String,
) -> TrayConfig {
  { id, title, icon_name, status: "Active", category: "ApplicationStatus" }
}

///|
/// 一个托盘（图标 + 右键菜单）。
pub struct Tray {
  cfg : TrayConfig
  menu : Menu
  mut revision : Int
}

///|
/// 新建托盘。
pub fn tray(cfg : TrayConfig) -> Tray {
  { cfg, menu: Menu::new(), revision: 1 }
}

///|
/// 注册一个右键菜单项，返回句柄。
pub fn Tray::on(
  self : Tray,
  key : String,
  title : String,
  handler : (ItemHandle) -> Unit,
) -> ItemHandle {
  self.menu.on(key, title, handler)
}

///|
/// 加一条分割线。
pub fn Tray::separator(self : Tray) -> Unit {
  self.menu.separator()
}

///|
/// 注册一个复选框。点击时自动翻转勾选状态，再调 handler。
pub fn Tray::checkbox(
  self : Tray,
  key : String,
  title : String,
  checked : Bool,
  handler : (ItemHandle) -> Unit,
) -> ItemHandle {
  self.menu.checkbox(key, title, checked, handler)
}

///|
/// 新建一个子菜单，返回构建器（可继续嵌套）。
pub fn Tray::submenu(self : Tray, key : String, title : String) -> SubMenu {
  self.menu.submenu(key, title)
}

///|
/// 按 key 取菜单项句柄（递归查找）。
pub fn Tray::item(self : Tray, key : String) -> ItemHandle? {
  self.menu.get(key)
}

///|
/// 运行时应用翻译表：按 key 递归改所有项标题（用于 i18n 切换）。
pub fn Tray::apply_translations(self : Tray, table : Map[String, String]) -> Unit {
  self.menu.apply_translations(table)
}

///|
/// 启动托盘：注册到桌面并常驻响应请求。会阻塞。
pub fn Tray::run(self : Tray) -> Result[Unit, Int] {
  let conn = match @dbus.connect_bus() {
    Err(e) => {
      return Err(e)
    }
    Ok(c) => c
  }
  match @dbus.hello(conn) {
    Err(e) => {
      @dbus.close(conn)
      return Err(e)
    }
    Ok(_) => ()
  }
  let pid = @dbus.getpid()
  let tray_name = "org.kde.StatusNotifierItem-" + pid.to_string() + "-1"
  match @dbus.request_name(conn, tray_name, 0, 2) {
    Err(e) => {
      @dbus.close(conn)
      return Err(e)
    }
    Ok(_) => ()
  }
  match @dbus.call_with_string(
    conn,
    "org.kde.StatusNotifierWatcher",
    "/StatusNotifierWatcher",
    "org.kde.StatusNotifierWatcher",
    "RegisterStatusNotifierItem",
    tray_name,
    3,
  ) {
    Err(e) => {
      @dbus.close(conn)
      return Err(e)
    }
    Ok(_) => ()
  }
  self.serve(conn)
  @dbus.close(conn)
  Ok(())
}

///|
/// 常驻服务循环。
fn Tray::serve(self : Tray, conn : @dbus.Connection) -> Unit {
  let mut serial = 100
  let mut running = true
  while running {
    match @dbus.recv_message(conn) {
      Err(_) => running = false
      Ok(raw) => {
        let fields = @dbus.parse_header_fields(raw)
        match @dbus.parse_message(raw) {
          None => ()
          Some(m) =>
            if m.msg_type.to_int() == 1 {
              serial = serial + 1
              self.handle(conn, m, fields, serial)
            }
        }
      }
    }
  }
}

///|
/// 处理一个来自桌面的方法调用。
fn Tray::handle(
  self : Tray,
  conn : @dbus.Connection,
  m : @dbus.Message,
  fields : @dbus.HeaderFields,
  serial : Int,
) -> Unit {
  // 回复必须指定 destination = 请求方，否则总线无法路由
  let dest = match fields.sender {
    Some(s) => s
    None => ""
  }
  let iface = match fields.interface {
    Some(s) => s
    None => ""
  }
  let name = match fields.member {
    Some(s) => s
    None => ""
  }
  if iface == "org.freedesktop.DBus.Properties" && name == "Get" {
    let prop = read_second_string(m.body)
    let value = if prop == "Menu" {
      let e = @dbus.Encoder::new()
      e.variant_object_path(MENU_PATH)
      e.finish()
    } else {
      @dbus.build_variant_string(self.property(prop))
    }
    reply(conn, dest, m.serial, value, "v", serial)
  } else if iface == "org.freedesktop.DBus.Properties" && name == "GetAll" {
    reply(conn, dest, m.serial, self.all_properties(), "a{sv}", serial)
  } else if iface == "com.canonical.dbusmenu" && name == "GetLayout" {
    // 入参 (parentID, recursionDepth, propertyNames)。前 8 字节是 i32 + i32。
    let parent_id = read_i32_at(m.body, 0)
    let depth = read_i32_at(m.body, 4)
    let layout = encode_layout(self.menu, self.revision, parent_id, depth)
    reply(conn, dest, m.serial, layout, "u(ia{sv}av)", serial)
  } else if iface == "com.canonical.dbusmenu" && name == "AboutToShow" {
    reply(conn, dest, m.serial, encode_bool(false), "b", serial)
  } else if iface == "com.canonical.dbusmenu" && name == "Event" {
    let (id, ev) = parse_event(m.body)
    if ev == "clicked" {
      let _ = self.menu.dispatch(id)
    }
    let empty : Bytes = Bytes::makei(0, fn(_) { 0 })
    reply(conn, dest, m.serial, empty, "", serial)
    // handler 里若改了菜单，通知桌面重新拉取布局
    if self.menu.is_dirty() {
      self.revision = self.revision + 1
      let body = @dbus.build_body_uu(self.revision, 0)
      let _ = @dbus.emit_signal(
        conn, MENU_PATH, "com.canonical.dbusmenu", "LayoutUpdated",
        body, "ui", serial + 1,
      )
      self.menu.clear_dirty()
    }
  } else {
    let empty : Bytes = Bytes::makei(0, fn(_) { 0 })
    reply(conn, dest, m.serial, empty, "", serial)
  }
}

///|
/// 发一条 METHOD_RETURN。
fn reply(
  conn : @dbus.Connection,
  dest : String,
  reply_serial : Int,
  body : Bytes,
  signature : String,
  serial : Int,
) -> Unit {
  let msg = @dbus.build_method_return(dest, reply_serial, body, signature, serial)
  let _ = @dbus.send_raw(conn, msg)
}

///|
/// 编码全部 SNI 属性为 a{sv}。
///
/// 关键：必须包含 `Menu`（对象路径）与 `ItemIsMenu`，
/// 否则桌面不知道这个托盘项带菜单，右键点了不会有反应。
fn Tray::all_properties(self : Tray) -> Bytes {
  let e = @dbus.Encoder::new()
  e.array_with(8, fn(dict) {
    dict.struct_with(fn(kv) {
      kv.string("Category")
      kv.variant_string(self.cfg.category)
    })
    dict.struct_with(fn(kv) {
      kv.string("Id")
      kv.variant_string(self.cfg.id)
    })
    dict.struct_with(fn(kv) {
      kv.string("Title")
      kv.variant_string(self.cfg.title)
    })
    dict.struct_with(fn(kv) {
      kv.string("Status")
      kv.variant_string(self.cfg.status)
    })
    dict.struct_with(fn(kv) {
      kv.string("IconName")
      kv.variant_string(self.cfg.icon_name)
    })
    dict.struct_with(fn(kv) {
      kv.string("Menu")
      kv.variant_object_path(MENU_PATH)
    })
    dict.struct_with(fn(kv) {
      kv.string("ItemIsMenu")
      kv.variant_bool(true)    // true：纯菜单项，KDE 只渲染一列
    })
  })
  e.finish()
}

///|
/// 按属性名取值。
fn Tray::property(self : Tray, prop : String) -> String {
  if prop == "Id" {
    self.cfg.id
  } else if prop == "Title" {
    self.cfg.title
  } else if prop == "IconName" {
    self.cfg.icon_name
  } else if prop == "Status" {
    self.cfg.status
  } else if prop == "Category" {
    self.cfg.category
  } else {
    ""
  }
}

///|
/// 读 body 里的第二个字符串（Properties.Get 的属性名）。
fn read_second_string(body : Bytes) -> String {
  if body.length() < 4 {
    return ""
  }
  let len1 = @dbus.read_le_u32_at(body, 0)
  let mut off = 4 + len1 + 1
  while off % 4 != 0 && off < body.length() {
    off = off + 1
  }
  match @dbus.read_dbus_string(body, off) {
    Some(s) => s
    None => ""
  }
}

///|
/// 读一个 有符号 小端 i32（用于 GetLayout 的 parentID / recursionDepth）。
fn read_i32_at(body : Bytes, off : Int) -> Int {
  if off + 4 > body.length() {
    return 0
  }
  let u = @dbus.read_le_u32_at(body, off)
  if u >= 0x80000000 {
    -(0xFFFFFFFF - u + 1)   // 读到的 u32 实际是负数补码，转回有符号
  } else {
    u
  }
}

///|
/// 兼容旧接口：无菜单的托盘。
pub fn run_tray(cfg : TrayConfig) -> Result[Unit, Int] {
  tray(cfg).run()
}

