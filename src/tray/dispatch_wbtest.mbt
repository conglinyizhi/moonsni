///|
/// dbusmenu Event 的请求体：i32 id 加一个 event id 字符串。
fn event_body(id : Int32, ev : String) -> Bytes {
  let e = @dbus.Encoder::new()
  e.i32(id)
  e.string(ev)
  e.finish()
}

///|
/// Event 是方法调用，必须回包。返回 None 会让 gdbus、plasmashell 一直等。
test "dbusmenu Event 必须回一个空回复" {
  let t = tray(default_tray_config("t", "t", "icon"))
  match
    t.reply_for("com.canonical.dbusmenu", "Event", event_body(1, "clicked")) {
    Some(r) => assert_eq(r.signature, "")
    None => {
      println("Event 返回了 None，调用方会挂到超时")
      assert_true(false)
    }
  }
}

///|
test "托盘点击类方法也都要回包" {
  let t = tray(default_tray_config("t", "t", "icon"))
  for member_name in ["Activate", "SecondaryActivate", "Scroll"] {
    let body = Bytes::makei(8, fn(_) { 0 })
    match t.reply_for("org.kde.StatusNotifierItem", member_name, body) {
      Some(r) => assert_eq(r.signature, "")
      None => {
        println("\{member_name} 返回了 None")
        assert_true(false)
      }
    }
  }
}

///|
/// 不认识的方法也必须回包，否则调用方会挂到超时。
test "未知成员也回包" {
  let t = tray(default_tray_config("t", "t", "icon"))
  match
    t.reply_for("org.example.Unknown", "Whatever", Bytes::makei(0, fn(_) { 0 })) {
    Some(r) => assert_eq(r.signature, "")
    None => {
      println("未知方法返回了 None，调用方会挂")
      assert_true(false)
    }
  }
}

///|
/// gdbus 在调用前会先 Introspect，不回包就干等三秒。
test "Introspect 返回能解析的 XML" {
  let t = tray(default_tray_config("t", "t", "icon"))
  let empty = Bytes::makei(0, fn(_) { 0 })
  match
    t.reply_for("org.freedesktop.DBus.Introspectable", "Introspect", empty) {
    Some(r) => {
      assert_eq(r.signature, "s")
      let xml = @utf8.decode(r.body)
      assert_true(xml.has_prefix("<node>"))
      assert_true(xml.contains("com.canonical.dbusmenu"))
    }
    None => assert_true(false)
  }
}

///|
test "Ping 返回空回复" {
  let t = tray(default_tray_config("t", "t", "icon"))
  match
    t.reply_for(
      "org.freedesktop.DBus.Peer",
      "Ping",
      Bytes::makei(0, fn(_) { 0 }),
    ) {
    Some(r) => assert_eq(r.signature, "")
    None => assert_true(false)
  }
}
