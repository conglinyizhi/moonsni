///|
/// 托盘菜单 + 运行时 i18n 切换。
///
/// 菜单全部用「描述 key」注册（menu.xxx），文案查翻译表。
/// 点「Language / 语言」子菜单里的选项，运行时整体切换语言，不用重建菜单。
fn main {
  let cfg = @sni.default_tray_config(
    "moonbit-i18n-demo",
    "MoonBit i18n Demo",
    "applications-system",
  )
  let t = @sni.tray(cfg)

  // —— 翻译表（用描述 key）。menu.* 会被 apply_translations 替换 ———
  let zh : Map[String, String] = {
    "menu.file": "文件",
    "menu.new": "新建文档",
    "menu.open": "打开…",
    "menu.save": "保存",
    "menu.edit": "编辑",
    "menu.undo": "撤销",
    "menu.redo": "重做",
    "menu.language": "语言",
    "menu.zh": "中文",
    "menu.en": "English",
    "menu.about": "关于本演示",
    "menu.about.text": "用 moonbit-dbus + moonbit-sni 构建",
  }
  let en : Map[String, String] = {
    "menu.file": "File",
    "menu.new": "New document",
    "menu.open": "Open…",
    "menu.save": "Save",
    "menu.edit": "Edit",
    "menu.undo": "Undo",
    "menu.redo": "Redo",
    "menu.language": "Language",
    "menu.zh": "中文",
    "menu.en": "English",
    "menu.about": "About this demo",
    "menu.about.text": "Built with moonbit-dbus + moonbit-sni",
  }

  // —— 注册菜单：扁平，语言切到顶层好找 ——
  t.on("menu.new", en["menu.new"], fn(item) {
    item.set_title(item.key() + " · done")
  })
  |> ignore
  t.on("menu.open", en["menu.open"], fn(_item) {  })
  |> ignore
  t.on("menu.save", en["menu.save"], fn(_item) {  })
  |> ignore

  t.separator()

  t.on("menu.undo", en["menu.undo"], fn(_item) {  })
  |> ignore
  t.on("menu.redo", en["menu.redo"], fn(_item) {  })
  |> ignore

  t.separator()

  t.checkbox("menu.save.on", "Auto-save", false, fn(item) {
    if item.checked() {
      item.set_title("Auto-save (on)")
    } else {
      item.set_title("Auto-save (off)")
    }
  })
  |> ignore

  t.separator()

  // 语言子菜单：验证 KDE 能正确弹出子项（参照 Go/systray 结构）
  let lang = t.submenu("menu.language", en["menu.language"])
  lang.on("menu.zh", en["menu.zh"], fn(_item) { t.apply_translations(zh) })
  |> ignore
  lang.on("menu.en", en["menu.en"], fn(_item) { t.apply_translations(en) })
  |> ignore

  t.separator()

  t.on("menu.about", en["menu.about"], fn(item) {
    item.set_title(en["menu.about.text"])
  })
  |> ignore

  // 初始按英文显示
  t.apply_translations(en)

  println("i18n tray start")
  match t.run() {
    Err(e) => println("tray failed errno=\{e}")
    Ok(_) => println("tray exited")
  }
}