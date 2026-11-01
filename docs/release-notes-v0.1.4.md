# v0.1.4 · 修「点了没反应」的真正根因

## 根因

`SessionScope` 只包住了首页：

```dart
return SessionScope(session: session, child: const ProjectListPage());
```

而 `Navigator.push` 出去的**所有**页面——新建项目、关于、项目详情、邀请、溯源——都挂在
`MaterialApp` 的 Navigator 上，**在 `SessionScope` 外面**。

它们一调用 `SessionScope.of(context)` 就抛异常：

- 新建项目：`_submit()` 里那句 `SessionScope.of(context)` 在 `try` 外面，
  异常直接中断函数 → **按钮点了没有任何反应**
- 名字预检查 `_checkName()` 同样，所以 `name-available` 一次都没发出去
- 关于页：`build()` 里就要 Session → **点进去白屏/退回**

服务端日志对得上：只有 `GET /api/projects`，从来没有 `POST /api/projects` 和 `name-available`。

## 修法

把 `SessionScope` 挂到 `MaterialApp.builder` 上——它在 Navigator 之上，能覆盖所有路由：

```dart
builder: (context, child) => SessionScope(session: session, child: child!),
home: _buildHome(),   // 这里不再包 SessionScope
```

## 顺带

- 创建页的失败提示同时弹 SnackBar：原来只写进页内 banner，而 banner 在 `ListView` 中间，
  用户停在按钮那一屏根本看不到，体感还是「没反应」
- 名字为空时自动聚焦输入框
- 版本 0.1.4+5

## 验证

- `flutter analyze`：0 error
- 服务端侧：创建项目 curl 实测 201（与版本无关，后端一直正常）

> 装之前请先卸载旧的 v0.1.1 / v0.1.2（debug 签名一致，直接覆盖安装也行）。
> 装好后进「关于」页，版本应显示 v0.1.4，服务器状态应为「正常 · xx ms」。
