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
/// 图标校验（set_icon 的错误拦截）单测。纯逻辑，不连总线。

///|
/// 合法图标：2x2，16 字节 ARGB —— 通过校验。
test "valid icon passes validate" {
  let icon = PixelIcon::make(2, 2, Bytes::makei(16, fn(_) { 0 }))
  assert_eq(icon.validate(), Ok(()))
}

///|
/// 0 宽或 0 高 —— 拦截。
test "zero size rejected" {
  assert_eq(
    PixelIcon::make(0, 2, Bytes::makei(0, fn(_) { 0 })).validate(),
    Err(NegativeSize),
  )
  assert_eq(
    PixelIcon::make(2, 0, Bytes::makei(0, fn(_) { 0 })).validate(),
    Err(NegativeSize),
  )
}

///|
/// 负尺寸 —— 拦截。
test "negative size rejected" {
  assert_eq(
    PixelIcon::make(-1, 2, Bytes::makei(0, fn(_) { 0 })).validate(),
    Err(NegativeSize),
  )
}

///|
/// 尺寸过大（>4096）—— 拦截，防桌面内存爆。
test "too large rejected" {
  let argb = Bytes::makei(4097 * 1 * 4, fn(_) { 0 })
  assert_eq(PixelIcon::make(4097, 1, argb).validate(), Err(TooLarge))
}

///|
/// ARGB 长度 != width*height*4 —— 拦截（画面会错位）。
test "length mismatch rejected" {
  // 2x2 应 16 字节，给 15
  assert_eq(
    PixelIcon::make(2, 2, Bytes::makei(15, fn(_) { 0 })).validate(),
    Err(LengthMismatch),
  )
  // 1x1 应 4 字节，给 8
  assert_eq(
    PixelIcon::make(1, 1, Bytes::makei(8, fn(_) { 0 })).validate(),
    Err(LengthMismatch),
  )
}

///|
/// 正常尺寸但对齐好的大字节能过。
test "exact size passes" {
  // 3x3 = 36 字节
  assert_eq(
    PixelIcon::make(3, 3, Bytes::makei(36, fn(_) { 0 })).validate(),
    Ok(()),
  )
}

///|
/// set_icon 反射校验：非法走 Err，合法走 Ok 且更新 pixmap。
test "set_icon validates and updates" {
  let t = @tray.tray(
    @tray.default_tray_config("test", "Test", "applications-system"),
  )
  // 非法
  assert_eq(
    t.set_icon(PixelIcon::make(0, 0, Bytes::makei(0, fn(_) { 0 }))),
    Err(NegativeSize),
  )
  // 合法
  assert_eq(
    t.set_icon(PixelIcon::make(2, 2, Bytes::makei(16, fn(_) { 0 }))),
    Ok(()),
  )
  // unchecked：即使非法也直接设置（高级开发者自负）
  t.set_icon_unchecked(PixelIcon::make(0, 0, Bytes::makei(0, fn(_) { 0 })))
}

///|
/// encode_pixmap 输出非空且以 a{sv} 数组长度前缀开头。
test "encode_pixmap produces bytes" {
  let icon = PixelIcon::make(2, 2, Bytes::makei(16, fn(_) { 0 }))
  let bytes = encode_pixmap([icon])
  assert_true(bytes.length() > 4)
  // 前 4 字节是 a{sv} 的数组长度（>0）
  assert_true(@dbus.read_le_u32_at(bytes, 0) > 0)
}
