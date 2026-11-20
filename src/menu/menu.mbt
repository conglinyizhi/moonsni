// Copyright 2026 conglinyizhi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
/// 托盘右键菜单（com.canonical.dbusmenu）。
///
/// 「路由注册」风格：用 key 注册菜单项与回调，注册时拿到句柄，
/// 之后随时能改标题 / 可用状态 / 勾选状态。
/// 支持普通项、分割线、复选框、以及任意层数的子菜单。

///|
/// 菜单项类型。变体通过 `pub(all)` 暴露，供 dbusmenu 子包跨包匹配。
#derive(Eq)
pub(all) enum NodeKind {
  Action // 普通可点项
  Separator // 分割线
  Checkbox // 复选框
  Submenu // 子菜单容器
}

///|
pub extend NodeKind with Eq::{not_equal, equal}

///|
/// 菜单树上的一个节点。
pub struct MenuNode {
  id : Int32
  key : String
  mut title : String
  mut enabled : Bool
  mut visible : Bool
  mut checked : Bool // 仅 Checkbox 有意义
  kind : NodeKind
  children : Array[MenuNode] // 子菜单的子项
  handler : (ItemHandle) -> Unit
}

///|
/// 菜单项句柄：注册时返回，也会传给回调。
pub struct ItemHandle {
  node : MenuNode
  menu : Menu
}

///|
/// 改标题。
pub fn ItemHandle::set_title(self : ItemHandle, title : String) -> Unit {
  self.node.title = title
  self.menu.dirty = true
}

///|
/// 改可用状态。
pub fn ItemHandle::set_enabled(self : ItemHandle, enabled : Bool) -> Unit {
  self.node.enabled = enabled
  self.menu.dirty = true
}

///|
/// 改可见性。
pub fn ItemHandle::set_visible(self : ItemHandle, visible : Bool) -> Unit {
  self.node.visible = visible
  self.menu.dirty = true
}

///|
/// 改勾选状态（复选框）。
pub fn ItemHandle::set_checked(self : ItemHandle, checked : Bool) -> Unit {
  self.node.checked = checked
  self.menu.dirty = true
}

///|
/// 切换勾选状态。
pub fn ItemHandle::toggle(self : ItemHandle) -> Unit {
  self.node.checked = !self.node.checked
  self.menu.dirty = true
}

///|
/// 读当前标题。
pub fn ItemHandle::title(self : ItemHandle) -> String {
  self.node.title
}

///|
/// 读勾选状态。
pub fn ItemHandle::checked(self : ItemHandle) -> Bool {
  self.node.checked
}

///|
/// 读 key。
pub fn ItemHandle::key(self : ItemHandle) -> String {
  self.node.key
}

///|
/// 一棵菜单。
pub struct Menu {
  items : Array[MenuNode] // 顶层菜单项
  mut next_id : Int32 // dbusmenu id 分配器（0 是根节点）
  mut dirty : Bool // 有改动，需要通知桌面
}

///|
/// 新建空菜单。
pub fn Menu::new() -> Menu {
  { items: [], next_id: 1, dirty: false, }
}

///|
/// 子菜单构建器：往某个子菜单节点里继续加项。
pub struct SubMenu {
  menu : Menu
  node : MenuNode
}

///|
/// 内部：造一个节点并分配 id。
fn make_node(
  menu : Menu,
  key : String,
  title : String,
  kind : NodeKind,
  checked : Bool,
  handler : (ItemHandle) -> Unit,
) -> MenuNode {
  let id = menu.next_id
  menu.next_id = id + 1
  {
    id,
    key,
    title,
    enabled: true,
    visible: true,
    checked,
    kind,
    children: [],
    handler,
  }
}

// —— 顶层菜单 API ——

///|
/// 注册一个普通菜单项。
pub fn Menu::on(
  self : Menu,
  key : String,
  title : String,
  handler : (ItemHandle) -> Unit,
) -> ItemHandle {
  let n = make_node(self, key, title, Action, false, handler)
  self.items.push(n)
  self.dirty = true
  { node: n, menu: self, }
}

///|
/// 加一条分割线。
pub fn Menu::separator(self : Menu) -> Unit {
  let n = make_node(self, "", "", Separator, false, fn(_x) {  })
  self.items.push(n)
  self.dirty = true
}

///|
/// 注册一个复选框。点击时会自动翻转勾选状态，然后调用 handler。
pub fn Menu::checkbox(
  self : Menu,
  key : String,
  title : String,
  checked : Bool,
  handler : (ItemHandle) -> Unit,
) -> ItemHandle {
  let n = make_node(self, key, title, Checkbox, checked, handler)
  self.items.push(n)
  self.dirty = true
  { node: n, menu: self, }
}

///|
/// 新建一个子菜单，返回构建器，可继续往里加项。
pub fn Menu::submenu(self : Menu, key : String, title : String) -> SubMenu {
  let n = make_node(self, key, title, Submenu, false, fn(_x) {  })
  self.items.push(n)
  self.dirty = true
  { menu: self, node: n, }
}

// —— 子菜单 API（与顶层镜像，可无限嵌套）——

///|
/// 往子菜单里加普通项。
pub fn SubMenu::on(
  self : SubMenu,
  key : String,
  title : String,
  handler : (ItemHandle) -> Unit,
) -> ItemHandle {
  let n = make_node(self.menu, key, title, Action, false, handler)
  self.node.children.push(n)
  self.menu.dirty = true
  { node: n, menu: self.menu, }
}

///|
/// 往子菜单里加分割线。
pub fn SubMenu::separator(self : SubMenu) -> Unit {
  let n = make_node(self.menu, "", "", Separator, false, fn(_x) {  })
  self.node.children.push(n)
  self.menu.dirty = true
}

///|
/// 往子菜单里加复选框。
pub fn SubMenu::checkbox(
  self : SubMenu,
  key : String,
  title : String,
  checked : Bool,
  handler : (ItemHandle) -> Unit,
) -> ItemHandle {
  let n = make_node(self.menu, key, title, Checkbox, checked, handler)
  self.node.children.push(n)
  self.menu.dirty = true
  { node: n, menu: self.menu, }
}

///|
/// 在子菜单里再开一层子菜单（可继续无限嵌套）。
pub fn SubMenu::submenu(
  self : SubMenu,
  key : String,
  title : String,
) -> SubMenu {
  let n = make_node(self.menu, key, title, Submenu, false, fn(_x) {  })
  self.node.children.push(n)
  self.menu.dirty = true
  { menu: self.menu, node: n, }
}

///|
/// 子菜单自身的句柄（可改它的标题等）。
pub fn SubMenu::handle(self : SubMenu) -> ItemHandle {
  { node: self.node, menu: self.menu, }
}

// —— 路由 / 查找 ——

///|
/// 按 dbusmenu id 递归查找节点。
/// 按 dbusmenu id 递归查找节点（供 dbusmenu 编解码跨包使用）。
pub fn find_node(items : Array[MenuNode], id : Int32) -> MenuNode? {
  let mut i = 0
  while i < items.length() {
    let n = items[i]
    if n.id == id {
      return Some(n)
    }
    match find_node(n.children, id) {
      Some(x) => return Some(x)
      None => ()
    }
    i = i + 1
  }
  None
}

///|
/// 点击事件：按 id 找到节点，复选框自动翻转，然后调用它的回调。
pub fn Menu::dispatch(self : Menu, id : Int32) -> Bool {
  match find_node(self.items, id) {
    None => false
    Some(n) => {
      if n.kind == Separator {
        return false
      }
      let h : ItemHandle = { node: n, menu: self, }
      if n.kind == Checkbox {
        n.checked = !n.checked
        self.dirty = true
      }
      (n.handler)(h)
      true
    }
  }
}

///|
/// 按 key 递归取句柄。
pub fn Menu::get(self : Menu, key : String) -> ItemHandle? {
  match find_by_key(self.items, key) {
    Some(n) => Some({ node: n, menu: self, })
    None => None
  }
}

///|
fn find_by_key(items : Array[MenuNode], key : String) -> MenuNode? {
  let mut i = 0
  while i < items.length() {
    let n = items[i]
    if n.key == key {
      return Some(n)
    }
    match find_by_key(n.children, key) {
      Some(x) => return Some(x)
      None => ()
    }
    i = i + 1
  }
  None
}

///|
/// 顶层菜单项数量。
pub fn Menu::len(self : Menu) -> Int32 {
  self.items.length()
}

///|
/// 菜单是否有未同步到桌面的改动。
pub fn Menu::is_dirty(self : Menu) -> Bool {
  self.dirty
}

///|
/// 清除改动标记。
pub fn Menu::clear_dirty(self : Menu) -> Unit {
  self.dirty = false
}

///|
/// 按 key 递归应用翻译表：把菜单里每个项的标题换成翻译表中的值。
/// 用于运行时切换语言（i18n）。
/// key 在翻译表中找不到时保留原标题。
pub fn Menu::apply_translations(
  self : Menu,
  table : Map[String, String],
) -> Unit {
  apply_to_items(self.items, table)
  self.dirty = true
}

///|
fn apply_to_items(items : Array[MenuNode], table : Map[String, String]) -> Unit {
  let mut i = 0
  while i < items.length() {
    let n = items[i]
    match table.get(n.key) {
      Some(new_title) => n.title = new_title
      None => ()
    }
    apply_to_items(n.children, table)
    i = i + 1
  }
}
