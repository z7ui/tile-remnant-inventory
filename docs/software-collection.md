# 软件合集：我做的几个 Android 小工具

都是自己用着不顺手、索性自己做的东西。全部开源，APK 也全部放在这台服务器上——不用去 GitHub 翻 Release，点一下就能下。

装之前有两点通用提醒：都是 **debug 或自签 release 签名**，装的时候系统会提示"未知来源"，允许即可；互相之间没有依赖，但两个 PIN 滑动输入**同一台机器只能装一个**。

## 余砖管家 · 瓷砖余料库存与匹配

装修切剩下的半块砖，以前只能堆在阳台靠记性。这个 App 把余料按尺寸入库，需要时输入"我要 60×60 一片"，它从现有余料里算出哪种切法最省，切完的边角料可以选择入库或丢弃，每一块砖都能溯源到最初那一整块。

界面按工地场景做：大按钮、数字键盘、离线可用、扫码加入项目。

- 版本 0.1.14
- 文章：[工地上的半块砖，终于有地方放了](https://www.z7ui.cn/tile-remnant-inventory/)
- 源码：[github.com/z7ui/tile-remnant-inventory](https://github.com/z7ui/tile-remnant-inventory)
- 下载：[tile-remnant-0.1.14.apk](https://www.z7ui.cn/apps-archive/downloads/tile-remnant-0.1.14.apk)

## 清抖 · 给抖音界面做减法

LSPosed 模块，作用域只有抖音。核心不是"屏蔽广告"，而是**能看懂当前在哪一页**——信息流、消息、直播间、个人页的判定逻辑完全不同，按页面决定隐藏哪些元素。附带标签栏过滤、自动跳过直播卡片、顶栏底栏位移等。

- 版本 0.72
- 文章：[清抖：给抖音的界面做一层会看状态的「减负」](https://www.z7ui.cn/qingdou-ui/)
- 源码：暂不公开（涉及抖音界面结构，留着省事）
- 下载：[qingdou-0.72-release.apk](https://www.z7ui.cn/apps-archive/downloads/qingdou-0.72-release.apk)

## 边触 EdgePad · 单手操作

把三星那套侧边触控板搬到小米。方向是对的，但卡在了系统手势这道墙上——边缘滑动优先级太高，第三方拿不到。文章里写了卡在哪里、试过哪些绕法。

- 版本 0.2
- 文章：[边触：把三星的单手操作搬到小米，卡在了系统手势这道墙上](https://www.z7ui.cn/edgepad/)
- 源码：[github.com/z7ui/edgepad](https://github.com/z7ui/edgepad)
- 下载：[edgepad-0.2-release.apk](https://www.z7ui.cn/apps-archive/downloads/edgepad-0.2-release.apk)

## 规则树 RuleTree · 可视化的「如果…则…否则」

把条件判断做成能存下来、能复用、能嵌套的东西。适合"充电时且连了公司 WiFi 就静音"这类组合条件，比系统自带的自动化更接近写代码的思路，但不需要写代码。

- 版本 0.12
- 文章：[规则树：把「如果……则……否则」做成能存下来的东西](https://www.z7ui.cn/ruletree/)
- 源码：[github.com/z7ui/ruletree](https://github.com/z7ui/ruletree)
- 下载：[ruletree-0.12-release.apk](https://www.z7ui.cn/apps-archive/downloads/ruletree-0.12-release.apk)

## 定时快捷 RoutineX · 到点自己把事做了

定时拉起指定 App 的快捷方式（比如签到）。和普通定时任务的区别是它会**校验结果**：拉起成功不等于事情做完，所以要回到界面确认"今天签没签"，三态记账（成功/失败/未确认），不把未知当成功。

- 版本 1.4
- 文章：[定时快捷 RoutineX：让小米到点自己把签到点掉](https://www.z7ui.cn/routinex/)
- 源码：[github.com/z7ui/routinex](https://github.com/z7ui/routinex)
- 下载：[routinex-1.4-release.apk](https://www.z7ui.cn/apps-archive/downloads/routinex-1.4-release.apk)

## 幕布 Curtain · 一层可调的黑

模仿三星幕布和游戏助推器的触控保护：一层透明度可调的黑盖住屏幕，设备照常运行。OLED 挂机省电、防止游戏更新时锁屏、夜里看视频不刺眼都能用。

- 版本 1.7
- 文章：[幕布 Curtain：把屏幕调暗到只剩一层黑，设备照常运行](https://www.z7ui.cn/curtain/)
- 源码：[github.com/z7ui/Curtain](https://github.com/z7ui/Curtain)
- 下载：[Curtain-1.7.apk](https://www.z7ui.cn/apps-archive/downloads/Curtain-1.7.apk)

## PIN 滑动输入 · HyperOS 版

把 Flyme 那种「按住不放、划过即输入」搬到 HyperOS 锁屏。普通 LSPosed 模块，作用域只有 SystemUI，单点输入不受影响——想输单个数字照样点。

- 版本 1.2
- 文章：[PIN 滑动输入：让 HyperOS 的锁屏支持 Flyme 那种「划过即输入」](https://www.z7ui.cn/pinswipe-hyperos/)
- 源码：[github.com/z7ui/PinSwipe](https://github.com/z7ui/PinSwipe)
- 下载：[PinSwipe-1.2.apk](https://www.z7ui.cn/apps-archive/downloads/PinSwipe-1.2.apk)

## PIN 滑动输入 for Galaxy · 三星版

同一套思路搬到三星 One UI，S25 Ultra 实测。和上面是两个独立项目，**同一台机器只能装一个**，装错了不会崩，但只认自己那套键盘几何。

- 版本 1.1
- 文章：[PIN 滑动输入 for Galaxy：三星 One UI 也支持按住不松手、划过即输入](https://www.z7ui.cn/pinswipe-galaxy/)
- 源码：[github.com/z7ui/PinSwipeForGalaxy](https://github.com/z7ui/PinSwipeForGalaxy)
- 下载：[PinSwipeForGalaxy-1.1.apk](https://www.z7ui.cn/apps-archive/downloads/PinSwipeForGalaxy-1.1.apk)

## 一点说明

这些包的签名都是我自己的，**换机器重装前先卸载**，否则会提示签名冲突。签名材料单独做了加密备份，不放公网。

有 bug 或者想要什么功能，评论区说就行。
