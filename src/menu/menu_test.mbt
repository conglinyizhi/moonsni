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
