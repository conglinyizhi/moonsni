///|
fn hex_of(b : Bytes) -> String {
  let out = StringBuilder::new()
  for i in 0..<b.length() {
    let v = b[i].to_int()
    let hi = (v >> 4) & 0xF
    let lo = v & 0xF
    out.write_char(Char::from_int(if hi < 10 { 48 + hi } else { 87 + hi }))
    out.write_char(Char::from_int(if lo < 10 { 48 + lo } else { 87 + lo }))
  }
  out.to_string()
}

///|
test "dump all_properties with pixmap" {
  let t = tray(default_tray_config("sid", "stitle", "sicon"))
  t.set_icon_unchecked(PixelIcon::make(1, 1, Bytes::makei(4, fn(_) { 0xFF })))
  let b = t.all_properties()
  println("HEX=\{hex_of(b)}")
}
