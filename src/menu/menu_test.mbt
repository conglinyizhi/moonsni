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
/// 验证句柄对象能否真正修改菜单项状态（MoonBit struct 的引用语义）。
test "handle mutates item" {
  let m = Menu::new()
  let h = m.on("qr", "识别二维码", fn(_item) {  })
  // 通过句柄改标题
  h.set_title("识别中…")
  // 从菜单里读回来，应该是新值
  let again = match m.get("qr") {
    Some(x) => x.title()
    None => "(not found)"
  }
  assert_eq(again, "识别中…")
  // 句柄自己读也应一致
  assert_eq(h.title(), "识别中…")
}

///|
/// 验证按 id 路由能调到正确的 handler。
test "dispatch routes by id" {
  let m = Menu::new()
  let hit = Array::make(1, "")
  let _a = m.on("a", "A", fn(item) { hit[0] = "a:" + item.title() })
  let _b = m.on("b", "B", fn(item) { hit[0] = "b:" + item.title() })
  // id 从 1 开始，第二项 id=2
  let ok = m.dispatch(2)
  assert_eq(ok, true)
  assert_eq(hit[0], "b:B")
}

///|
/// dispatch 不存在的 id 应返回 false，不调用任何 handler。
test "dispatch unknown id returns false" {
  let m = Menu::new()
  let hit = Array::make(1, "")
  let _a = m.on("a", "A", fn(_item) { hit[0] = "AHIT" })
  // id 从 1 开始，999 不存在
  let ok = m.dispatch(999)
  assert_eq(ok, false)
  assert_eq(hit[0], "") // 没被调用
}

///|
/// 分隔线加入后菜单长度增加。
test "separator adds to count" {
  let m = Menu::new()
  m.on("a", "A", fn(_item) {  }) |> ignore
  let count_before = m.len()
  m.separator()
  assert_eq(m.len(), count_before + 1)
}

///|
/// 顶层与子菜单的 dispatch 都能路由（递归）。
test "dispatch recurses into submenu" {
  let m = Menu::new()
  let hit = Array::make(1, "")
  m.on("top", "Top", fn(_item) { hit[0] = "top" }) |> ignore
  let lang = m.submenu("lang", "Language")
  lang.on("zh", "中文", fn(_item) { hit[0] = "zh" }) |> ignore
  // zh 是 lang 的子项，id 在第 3 个（1=top, 2=lang, 3=zh）
  let ok = m.dispatch(3)
  assert_eq(ok, true)
  assert_eq(hit[0], "zh")
}

///|
/// get 找不到 key 返回 None。
test "get unknown key returns None" {
  let m = Menu::new()
  let _a = m.on("a", "A", fn(_item) {  })
  assert_true(m.get("nope") is None)
}

///|
/// 复选框 dispatch 自动翻转 checked。
test "checkbox toggles on dispatch" {
  let m = Menu::new()
  let h = m.checkbox("dark", "Dark", false, fn(item) { let _ = item.checked() })
  assert_eq(h.checked(), false)
  // 找到 checkbox 的 id 并 dispatch
  // checkbox 是第 1 项（id=1）
  let _ = m.dispatch(1)
  assert_eq(h.checked(), true)
}

///|
/// i18n：apply_translations 递归改标题，unmapped key 保留。
test "apply_translations recurses and leaves unmapped" {
  let m = Menu::new()
  m.on("menu.file", "File", fn(_item) {  }) |> ignore
  m.on("menu.open", "Open", fn(_item) {  }) |> ignore
  let sub = m.submenu("menu.language", "Language")
  sub.on("menu.zh", "Chinese", fn(_item) {  }) |> ignore

  let zh : Map[String, String] = {
    "menu.file": "文件",
    "menu.language": "语言",
    "menu.zh": "中文",
  }
  m.apply_translations(zh)

  // menu.file 被翻译
  match m.get("menu.file") {
    Some(it) => assert_eq(it.title(), "文件")
    None => fail("file not found")
  }
  // menu.open（未映射）保留原标题
  match m.get("menu.open") {
    Some(it) => assert_eq(it.title(), "Open")
    None => fail("open not found")
  }
  // 子菜单项也被递归翻译
  match m.get("menu.zh") {
    Some(it) => assert_eq(it.title(), "中文")
    None => fail("zh not found")
  }
}