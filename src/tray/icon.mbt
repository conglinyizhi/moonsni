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
/// 托盘图标（像素型）与校验。
///
/// SNI 的托盘图标有两种来源：
///  - `IconName`：freedesktop 图标主题里的名字（如 "applications-system"），
///    由桌面去主题里找图标。**已支持且稳定。**
///  - `IconPixmap`：直接传像素数据（ARGB），由程序生成。
///
/// ⚠️ **实验性**：IconPixmap 的 D-Bus 编码（`a(iiibay)`）在 KDE 上尚未验证通过
/// （含图标时会导致桌面断连）。API（PixelIcon/set_icon/校验分层）已就绪并单元测试，
/// 但**编码需在真实桌面环境完善后才能实际使用**。推荐先只用 IconName 图标。
///
/// 程序生成的图片在纯 MoonBit 里没有图像解码库，所以这里用「已解码的像素
/// 数据」表示：一个 PixelIcon 是 (宽, 高, ARGB 字节流)。

///|
/// 一个像素图标（SNI IconPixmap 的一项）。
/// `argb` 是 width*height*4 字节，每像素 4 字节，顺序 A, R, G, B。
pub struct PixelIcon {
  width : Int32
  height : Int32
  argb : Bytes
}

///|
/// 图标校验错误。变体通过 pub(all) 暴露，供测试/高级开发者区分具体错误。
#derive(Debug, Eq)
pub(all) enum IconError {
  EmptySize
  NegativeSize
  TooLarge
  LengthMismatch
}

///|
pub extend IconError with Debug::{to_repr}

///|
pub extend IconError with Eq::{not_equal, equal}

///|
/// 新建一个像素图标。不做校验（构造是纯数据）。
pub fn PixelIcon::make(
  width : Int32,
  height : Int32,
  argb : Bytes,
) -> PixelIcon {
  { width, height, argb, }
}

///|
/// 校验一个像素图标。返回 Ok(()) 或 IconError。
pub fn PixelIcon::validate(self : PixelIcon) -> Result[Unit, IconError] {
  if self.width <= 0 || self.height <= 0 {
    return Err(NegativeSize)
  }
  // 防御超大尺寸（防止用户误传导致桌面分配巨大内存或卡死）
  if self.width > 4096 || self.height > 4096 {
    return Err(TooLarge)
  }
  // ARGB 字节数必须是 width*height*4，否则画面错位
  let expect = self.width * self.height * 4
  if self.argb.length() != expect {
    return Err(LengthMismatch)
  }
  if expect == 0 {
    return Err(EmptySize)
  }
  Ok(())
}

///|
/// 把一个像素图标编码成 SNI IconPixmap 的一项 `(iiay)`（width, height, stride=0?, argb）。
/// 实际 D-Bus 签名是 `(iiibay)`；这里编码 `(i i i ay)` 中的 (w, h, stride, argb)。
/// 注：stride 按规范通常为 0 或每行字节数。这里用每行字节数（width*4）。
pub fn PixelIcon::encode(self : PixelIcon, enc : @dbus.Encoder) -> Unit {
  // `(iiibay)` 成员最大对齐是 int32(4)，所以 struct 对齐 4（不能用默认 8）
  enc.struct_with_align(4, fn(s) {
    s.i32(self.width)
    s.i32(self.height)
    s.i32(self.width * 4) // stride：每行字节数
    s.array(1, self.argb) // ay：ARGB 字节流
  })
}

///|
/// 把多个像素图标编码成 `a(iiibay)`（SNI IconPixmap 的类型）。
pub fn encode_pixmap(icons : Array[PixelIcon]) -> Bytes {
  let e = @dbus.Encoder::new()
  e.array_with(4, fn(a) {
    let mut i = 0
    while i < icons.length() {
      icons[i].encode(a)
      i = i + 1
    }
  })
  e.finish()
}
