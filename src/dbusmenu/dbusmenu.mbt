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
/// com.canonical.dbusmenu 协议编解码。
///
/// 桌面通过这个接口取菜单结构，并在用户点击时回调我们。
/// 支持普通项、分割线、复选框、以及任意层数的子菜单。

///|
/// 编码 GetLayout 的返回值：`(u(ia{sv}av))`
///   u          revision
///   (ia{sv}av) 根节点：id / 属性字典 / 子项（每个子项是一个 variant）
///
/// parentID 与 recursionDepth 对应 GetLayout 的入参：
///  - parentID = 0  返回整棵菜单（根节点，含全部嵌套子项）
///  - parentID = 非 0  返回「该节点自身」作为根（KDE 对子菜单项单独取这一层时用）
///  - recursionDepth = -1 不限深度；0 只当前层；>0 为剩余层数
pub fn encode_layout(
  menu : @menu.Menu,
  revision : Int32,
  parent_id : Int32,
  depth : Int32,
) -> Bytes {
  let enc = @dbus.Encoder::new()
  enc.u32(revision)
  if parent_id == 0 {
    // 根节点：id=0，渲染所有顶层项（含嵌套子项，作为一棵完整树）
    enc.struct_with(fn(root) {
      root.i32(0)
      root.array_with(8, fn(_props) {
        // 根节点无特殊属性
      })
      root.array_with(1, fn(children) {
        let mut i = 0
        while i < menu.items.length() {
          encode_node(children, menu.items[i], depth)
          i = i + 1
        }
      })
    })
  } else {
    // 子菜单：返回「该节点自身」作为根（id / props / children 同一层，不包裹）
    match @menu.find_node(menu.items, parent_id) {
      None =>
        enc.struct_with(fn(root) {
          root.i32(0)
          root.array_with(8, fn(_props) {  })
          root.array_with(1, fn(_children) {  })
        })
      Some(n) => encode_struct_root(enc, n, depth)
    }
  }
  enc.finish()
}

///|
/// 把一个节点编码成顶层的 `(ia{sv}av)` 结构体（不带 variant 签名）。
/// 用于非根分支：KDE 单独取某个子菜单项时，期望拿到该节点自身。
fn encode_struct_root(
  out : @dbus.Encoder,
  node : @menu.MenuNode,
  depth : Int32,
) -> Unit {
  out.struct_with(fn(n) {
    n.i32(node.id)
    // 属性字典
    n.array_with(8, fn(p) { encode_props(p, node) })
    // 子项（递归）
    n.array_with(1, fn(kids) {
      if depth != 0 {
        let child_depth = if depth < 0 { -1 } else { depth - 1 }
        let mut i = 0
        while i < node.children.length() {
          encode_node(kids, node.children[i], child_depth)
          i = i + 1
        }
      }
    })
  })
}

///|
/// 编码一个菜单节点的属性字典 `a{sv}`。
fn encode_props(p : @dbus.Encoder, node : @menu.MenuNode) -> Unit {
  if node.kind == Separator {
    p.struct_with(fn(e) {
      e.string("type")
      e.variant_string("separator")
    })
  } else {
    p.struct_with(fn(e) {
      e.string("label")
      e.variant_string(node.title)
    })
    p.struct_with(fn(e) {
      e.string("enabled")
      e.variant_bool(node.enabled)
    })
    p.struct_with(fn(e) {
      e.string("visible")
      e.variant_bool(node.visible)
    })
    // toggle-type / toggle-state：Go 版 systray 对普通项也带（空串），
    // KDE 依赖这两个属性区分项的类型，缺失可能渲染异常。
    if node.kind == Checkbox {
      p.struct_with(fn(e) {
        e.string("toggle-type")
        e.variant_string("checkmark")
      })
      p.struct_with(fn(e) {
        e.string("toggle-state")
        e.variant_i32(if node.checked { 1 } else { 0 })
      })
    } else {
      p.struct_with(fn(e) {
        e.string("toggle-type")
        e.variant_string("")
      })
      p.struct_with(fn(e) {
        e.string("toggle-state")
        e.variant_i32(0)
      })
    }
    if node.kind == Submenu {
      p.struct_with(fn(e) {
        e.string("children-display")
        e.variant_string("submenu")
      })
    }
  }
}

///|
/// 递归编码一个菜单节点（作为 av 数组里的一个 variant）。
/// depth 控制递归层数：-1 不限；0 只当前节点；>0 递减。
/// 渲染「直接子项」当且仅当 depth != 0（与 systray copyLayout 语义一致）。
fn encode_node(
  out : @dbus.Encoder,
  node : @menu.MenuNode,
  depth : Int32,
) -> Unit {
  out.signature("(ia{sv}av)") // variant 的签名
  out.struct_with(fn(n) {
    n.i32(node.id)
    // 属性字典
    n.array_with(8, fn(p) { encode_props(p, node) })
    // 子项（递归）。depth != 0 才渲染直接子项；传给子项时递减一层。
    n.array_with(1, fn(kids) {
      if depth != 0 {
        let child_depth = if depth < 0 { -1 } else { depth - 1 }
        let mut i = 0
        while i < node.children.length() {
          encode_node(kids, node.children[i], child_depth)
          i = i + 1
        }
      }
    })
  })
}

///|
/// 解析 Event 调用的 body：`(i s v u)` -> (id, eventId)
pub fn parse_event(body : Bytes) -> (Int32, String) {
  if body.length() < 8 {
    return (0, "")
  }
  let id = @dbus.read_le_u32_at(body, 0)
  let ev = match @dbus.read_dbus_string(body, 4) {
    Some(s) => s
    None => ""
  }
  (id, ev)
}

///|
/// 编码 AboutToShow 的返回值：`b`
pub fn encode_bool(v : Bool) -> Bytes {
  let enc = @dbus.Encoder::new()
  enc.bool(v)
  enc.finish()
}
