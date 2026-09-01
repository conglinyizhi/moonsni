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
  id : String // 应用 id
  title : String // 标题
  icon_name : String // freedesktop 图标主题里的图标名
  status : String // "Active" / "Passive" / "NeedsAttention"
  category : String // "ApplicationStatus" 等
}

///|
/// 常用默认值：Active + ApplicationStatus。
pub fn default_tray_config(
  id : String,
  title : String,
  icon_name : String,
) -> TrayConfig {
  { id, title, icon_name, status: "Active", category: "ApplicationStatus", }
}

///|
/// 一个托盘（图标 + 右键菜单）。
/// 除了右键菜单，还能响应左键 / 中键（同键）点击与滚轮。
pub struct Tray {
  cfg : TrayConfig
  menu : @menu.Menu
  mut revision : Int
  pixmap : Array[PixelIcon]               // 当前像素图标（IconPixmap）
  mut icon_dirty : Bool // 图标变了，需要发 NewIcon 信号
  mut activate_handler : (Int, Int) -> Unit // 左键：桌面坐标 (x, y)
  mut secondary_handler : (Int, Int) -> Unit // 中键：桌面坐标 (x, y)
  mut scroll_handler : (Int, Int) -> Unit // 滚轮：(delta, orientation)
}

///|
/// 新建托盘。
pub fn tray(cfg : TrayConfig) -> Tray {
  {
    cfg,
    menu: @menu.Menu::new(),
    revision: 1,
    pixmap: [],
    icon_dirty: false,
    activate_handler: fn(_x, _y) {  },
    secondary_handler: fn(_x, _y) {  },
    scroll_handler: fn(_d, _o) {  },
  }
}

///|
/// 注册一个右键菜单项，返回句柄。
pub fn Tray::on(
  self : Tray,
  key : String,
  title : String,
  handler : (@menu.ItemHandle) -> Unit,
) -> @menu.ItemHandle {
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
  handler : (@menu.ItemHandle) -> Unit,
) -> @menu.ItemHandle {
  self.menu.checkbox(key, title, checked, handler)
}

///|
/// 新建一个子菜单，返回构建器（可继续嵌套）。
pub fn Tray::submenu(
  self : Tray,
  key : String,
  title : String,
) -> @menu.SubMenu {
  self.menu.submenu(key, title)
}

///|
/// 按 key 取菜单项句柄（递归查找）。
pub fn Tray::item(self : Tray, key : String) -> @menu.ItemHandle? {
  self.menu.get(key)
}

///|
/// 运行时应用翻译表：按 key 递归改所有项标题（用于 i18n 切换）。
pub fn Tray::apply_translations(
  self : Tray,
  table : Map[String, String],
) -> Unit {
  self.menu.apply_translations(table)
}

///|
/// 注册左键点击回调。参数为桌面坐标 (x, y)。
pub fn Tray::on_click(self : Tray, f : (Int, Int) -> Unit) -> Unit {
  self.activate_handler = f
}

///|
/// 注册中键点击回调。参数为桌面坐标 (x, y)。
pub fn Tray::on_middle_click(self : Tray, f : (Int, Int) -> Unit) -> Unit {
  self.secondary_handler = f
}

///|
/// 注册滚轮回调。参数为 (delta, orientation)，orientation 0=垂直 1=水平。
pub fn Tray::on_scroll(self : Tray, f : (Int, Int) -> Unit) -> Unit {
  self.scroll_handler = f
}

///|
/// 设置托盘图标为像素图标（IconPixmap）。**带校验**，适合初级开发者。
///
/// 校验：尺寸必须为正、不能过大（>4096）、ARGB 字节数必须等于 width*height*4。
/// 任一不满足返回 Err(IconError)，原图标保持不变。
/// 成功时设置图标并标记需要发 NewIcon 信号（桌面会刷新）。
pub fn Tray::set_icon(self : Tray, icon : PixelIcon) -> Result[Unit, IconError] {
  match icon.validate() {
    Err(e) => Err(e)
    Ok(_) => {
      self.pixmap.clear()
      self.pixmap.push(icon)
      self.icon_dirty = true
      Ok(())
    }
  }
}

///|
/// 设置托盘图标为多个像素图标（不同尺寸），**带校验**。
pub fn Tray::set_icons(
  self : Tray,
  icons : Array[PixelIcon],
) -> Result[Unit, IconError] {
  let mut i = 0
  while i < icons.length() {
    match icons[i].validate() {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    i = i + 1
  }
  self.pixmap.clear()
  let mut i = 0
  while i < icons.length() {
    self.pixmap.push(icons[i])
    i = i + 1
  }
  self.icon_dirty = true
  Ok(())
}

///|
/// 设置托盘图标为像素图标，**跳过所有校验**，适合高级开发者自行保证数据正确。
///
/// 风险自负：尺寸/数据不对可能导致画面错乱或桌面资源占用异常。
pub fn Tray::set_icon_unchecked(self : Tray, icon : PixelIcon) -> Unit {
  self.pixmap.clear()
  self.pixmap.push(icon)
  self.icon_dirty = true
}

///|
/// 清除像素图标，回退到 IconName（freedesktop 主题图标名）。
pub fn Tray::clear_pixmap(self : Tray) -> Unit {
  self.pixmap.clear()
  self.icon_dirty = true
}

///|
/// 当前像素图标数量（调试 / 自检用）。
pub fn Tray::pixmap_count(self : Tray) -> Int {
  self.pixmap.length()
}

///|
/// 启动托盘：注册到桌面并常驻响应请求。会阻塞。
pub fn Tray::run(self : Tray) -> Result[Unit, Int] {
  let tray_ref = Ref::new(self)
  let server = match @dbus.Server::connect() {
    Err(e) => return Err(e)
    Ok(s) => s
  }
  match @dbus.Server::hello(server) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let pid = @dbus.getpid()
  let tray_name = "org.kde.StatusNotifierItem-" + pid.to_string() + "-1"
  match @dbus.Server::request_name(server, tray_name, 0) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match
    @dbus.Server::call_with_string(
      server, "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
      "RegisterStatusNotifierItem", tray_name, 3,
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  // 常驻服务循环：把方法调用分发给 tray（通过 Ref 捕获可变状态）
  @dbus.Server::serve(server, fn(s, ctx) {
    let t = tray_ref.val
    t.handle(s, ctx)
  })
  Ok(())
}

///|
/// 处理一个来自桌面的方法调用。返回要回复的内容（None 则不回）。
fn Tray::handle(
  self : Tray,
  server : @dbus.Server,
  ctx : @dbus.DispatchCtx,
) -> @dbus.Reply? {
  let iface = ctx.iface
  let name = ctx.member
  if iface == "org.freedesktop.DBus.Properties" && name == "Get" {
    let prop = read_second_string(ctx.body)
    let value = if prop == "Menu" {
      let e = @dbus.Encoder::new()
      e.variant_object_path(MENU_PATH)
      e.finish()
    } else {
      @dbus.build_variant_string(self.property(prop))
    }
    Some({ body: value, signature: "v", })
  } else if iface == "org.freedesktop.DBus.Properties" && name == "GetAll" {
    Some({ body: self.all_properties(), signature: "a{sv}", })
  } else if iface == "com.canonical.dbusmenu" && name == "GetLayout" {
    let parent_id = read_i32_at(ctx.body, 0)
    let depth = read_i32_at(ctx.body, 4)
    let layout = @dbusmenu.encode_layout(
      self.menu,
      self.revision,
      parent_id,
      depth,
    )
    Some({ body: layout, signature: "u(ia{sv}av)", })
  } else if iface == "com.canonical.dbusmenu" && name == "AboutToShow" {
    Some({ body: @dbusmenu.encode_bool(false), signature: "b", })
  } else if iface == "com.canonical.dbusmenu" && name == "Event" {
    let (id, ev) = @dbusmenu.parse_event(ctx.body)
    if ev == "clicked" {
      let _ = self.menu.dispatch(id)
    }
    // handler 里若改了菜单，通知桌面重新拉取布局
    if self.menu.is_dirty() {
      self.revision = self.revision + 1
      let body = @dbus.build_body_uu(self.revision, 0)
      let _ = @dbus.Server::emit_signal(
        server,
        MENU_PATH,
        "com.canonical.dbusmenu",
        "LayoutUpdated",
        body,
        "ui",
      )
      self.menu.clear_dirty()
    }
    // set_icon 之类改了图标，发 NewIcon 信号让桌面刷新
    if self.icon_dirty {
      let empty : Bytes = Bytes::makei(0, fn(_) { 0 })
      let _ = @dbus.Server::emit_signal(
        server, "/StatusNotifierItem", "org.kde.StatusNotifierItem", "NewIcon", empty,
        "",
      )
      self.icon_dirty = false
    }
    None // 菜单事件不需要回复
  } else if iface == "org.kde.StatusNotifierItem" && name == "Activate" {
    // 左键点击：body 是 (i32 x, i32 y)
    let (x, y) = read_xy(ctx.body)
    let h = self.activate_handler
    h(x, y)
    Some({ body: Bytes::makei(0, fn(_) { 0 }), signature: "", })
  } else if iface == "org.kde.StatusNotifierItem" && name == "SecondaryActivate" {
    let (x, y) = read_xy(ctx.body)
    let h = self.secondary_handler
    h(x, y)
    Some({ body: Bytes::makei(0, fn(_) { 0 }), signature: "", })
  } else if iface == "org.kde.StatusNotifierItem" && name == "Scroll" {
    // body 是 (i32 delta, i32 orientation)
    let delta = read_i32_at(ctx.body, 0)
    let orientation = read_i32_at(ctx.body, 4)
    let h = self.scroll_handler
    h(delta, orientation)
    Some({ body: Bytes::makei(0, fn(_) { 0 }), signature: "", })
  } else {
    None
  }
}

///|
/// 发一条 METHOD_RETURN。

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
    // 有像素图标时，额外提供 IconPixmap（桌面优先用它显示，否则用 IconName）
    if self.pixmap.length() > 0 {
      dict.struct_with(fn(kv) {
        kv.string("IconPixmap")
        let icons = self.pixmap
        kv.variant_with("a(iiibay)", fn(v) {
          v.array_with(4, fn(a) {
            let mut i = 0
            while i < icons.length() {
              icons[i].encode(a)
              i = i + 1
            }
          })
        })
      })
    }
    dict.struct_with(fn(kv) {
      kv.string("Menu")
      kv.variant_object_path(MENU_PATH)
    })
    dict.struct_with(fn(kv) {
      kv.string("ItemIsMenu")
      kv.variant_bool(true) // true：纯菜单项，KDE 只渲染一列
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
    -(0xFFFFFFFF - u + 1) // 读到的 u32 实际是负数补码，转回有符号
  } else {
    u
  }
}

///|
/// 读两个 i32（SNI Activate/SecondaryActivate 的桌面坐标 x,y）。
fn read_xy(body : Bytes) -> (Int, Int) {
  (read_i32_at(body, 0), read_i32_at(body, 4))
}

///|
/// 兼容旧接口：无菜单的托盘。
pub fn run_tray(cfg : TrayConfig) -> Result[Unit, Int] {
  tray(cfg).run()
}
