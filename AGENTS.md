# moonsni AGENTS.md

This is a [MoonBit](https://docs.moonbitlang.com) project — the KDE/freedesktop
system tray library built on [moondbus](https://github.com/conglinyizhi/moondbus).

## What this library is

A pure-MoonBit implementation of the freedesktop
[StatusNotifierItem](https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/)
(SNI) spec — tray icon + right-click menu + pointer/scroll events. No GTK, no
Qt, no `libappindicator`. The D-Bus protocol itself lives in `moondbus`; this
library wires it into a tray service.

## Project structure

```
moonsni/
├── moon.pkg              # 根聚合包（提供文档编译环境 + 一键入口；本身不导出符号）
├── README.mbt.md         # 主文档，含 mbt check 示例（被 moon check/test 验证）
├── src/
│   ├── menu/             # 纯菜单数据模型（Menu/ItemHandle/SubMenu/NodeKind/i18n）——零 D-Bus
│   ├── dbusmenu/         # 纯 com.canonical.dbusmenu 线协议编解码（encode_layout/parse_event）
│   └── tray/             # 完整托盘（Tray/TrayConfig/PixelIcon 图标/事件）——依赖 menu+dbusmenu+moondbus
├── cmd/tray-demo/        # 可运行的完整托盘示例（is-main）
└── examples/doc/         # 额外的可编译示例集（mbt check）
```

**渐进式层级**（这是本库的核心理念）：

- `src/menu` 是**纯数据**，零 D-Bus 依赖——用户只想建菜单（不要托盘）时用它。
- `src/dbusmenu` 是**纯编解码**，只依赖 `menu` + moondbus 的 `Encoder`。
- `src/tray` 依赖上面两者 + moondbus 连接，是**完整托盘**。

子包 import 路径（用户侧）：

```
clyzhi/moonsni/src/menu   @menu
clyzhi/moonsni/src/dbusmenu @dbusmenu
clyzhi/moonsni/src/tray   @tray
```

## Package conventions

- **每个子目录是一个 package**（MoonBit 目录即包），各自有 `moon.pkg`。
- 依赖关系必须**单向无环**：`dbusmenu -> menu`，`tray -> menu + dbusmenu`。
  新增子包时不要引入反向依赖。
- 根 `moon.pkg` 只 import 三个子包 + moondbus 作为文档编译环境（它不做 re-export，
  因为 MoonBit 无跨包 re-export 机制）。
- `mnemonics`: `@menu`/`@dbusmenu`/`@tray` 别名在各自的 `moon.pkg` 里用
  `@alias` 显式声明，不要依赖默认别名推断（路径末段与别名不一致时）。

## Coding convention

- MoonBit 块风格，块间用 `///|`，块序无关，可逐块重构。
- `pub struct` 的字段默认跨包**可读不可构造**；需要跨包构造时用 `pub(all)`。
- 枚举变体跨包构造/匹配需要 `pub(all)`（如 `NodeKind`、`IconError`）。
- 函数字段（回调）在方法里调用需先取局部变量：`let h = self.handler; h(x, y)`，
  直接 `self.handler(x, y)` 会被解析成方法调用而报错。
- 跨包调用必须 `@pkg.fn()`（`@menu.Menu::new()` 等）。

## dbusmenu protocol details (坑，必读)

1. **`toggle-type` / `toggle-state` 必须出现在每个普通项上**（普通项/子菜单用空串
   和 `0`，checkbox 用 `"checkmark"` 和 `1/0`）。KDE 靠它们区分项的类型；缺失时
   子菜单可能被渲染成**整个父菜单**（踩过的坑）。
2. **`GetLayout` 收到 `(parentID, recursionDepth)` 参数必须尊重**：
   - `parentID = 0` 返回整棵菜单（根节点）
   - `parentID = 子菜单 id` 只返回**该子菜单子树**作为根
   - `recursionDepth` 控制展开层数（`-1` 不限）
   否则点击子菜单会显示整个父菜单（踩过的坑）。
3. **回复必须带 `destination = 请求方 sender`**，否则总线无法路由。
4. `IconPixmap` 的类型是 `a(iiibay)`，每项 `(width, height, stride, argb_bytes)`，
   stride 通常 = width*4。**注意：此编码在 KDE 上尚未验证通过**（变异体嵌套对齐问题
   会导致桌面断连），`PixelIcon` 系列是实验性 API，别当成可用功能。

## Testing

- 单元测试：`*_test.mbt`（黑盒）放各子包目录。
- 文档测试：`README.mbt.md` 里的 `mbt check` 块会被 `moon check`/`moon test` 执行，
  所以**改公共 API 时必须同步更新 README 里的示例**，否则 CI 会挂。
- 运行 `moon test --target native` 验证全部（含文档示例）。当前用 `MOON_CC=gcc`。
- 断言用 `assert_eq` / `assert_true`；纯逻辑测试不要连总线。

## Tooling

- `moon fmt` 格式化。
- `moon info` 生成 `.mbti`（公共 API 信号），改动后检查 diff。
- 提交前顺序：`moon info && moon fmt`，再 `moon test --target native`。
- `pkg.generated.mbti` 建议纳入版本控制（库包）；`cmd/tray-demo`（main 包）的
  mbti **不要提交**（已在 `.gitignore`）。

## Build / run

```
MOON_CC=gcc moon build --target native
MOON_CC=gcc moon run cmd/tray-demo --target native   # 启动托盘
```

需要 `MOON_CC=gcc`（若工具链找不到 C 编译器）。
