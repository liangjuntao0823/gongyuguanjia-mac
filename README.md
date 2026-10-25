# 公寓管家（Mac 版）

参照 iOS 版「公寓管家」功能完整重写的 macOS 应用（macOS 15+，SwiftUI + SwiftData）。

- 与 iOS 版共用同一套腾讯云 COS + 云函数后台（房源/名片/二维码/分享 H5/备份/统计全互通）
- 7 大板块：工作台 / 房源 / 成交 / 收租 / 包租 / 汇总 / 设置
- 房源分享 H5（单房/合集/公开选房链接）、云端同步、备份恢复、自动备份、本地通知提醒
- 按 macOS 标准重建：侧边栏导航 + 主内容区，所有详情/弹窗均带明确关闭按钮（不依赖滑屏手势）

## 构建

```bash
xcodebuild -project GongyuGuanjiaMac.xcodeproj -scheme GongyuGuanjiaMac -configuration Release build
```

或直接 GitHub Actions（.github/workflows/build.yml）自动构建 unsigned .app。

## 首次使用

1. 打开 App，进入「设置 → 房源分享 → 云端配置」填写你的腾讯云 COS 密钥（与 iOS 版同一套桶）
2. 填写云函数地址（与 iOS 版相同）
3. 数据即与 iOS 版互通：房源同步、分享 H5、备份均实时

## 目录

```
GongyuGuanjiaMac/
├── App.swift              入口 + 双容器 + 启动初始化
├── Theme.swift            主题
├── MacBridge.swift        iOS→macOS 桥接（剪贴板/文件面板/分享/保存）
├── Models/                SwiftData 模型
├── Services/              云端/备份/H5/媒体/通知/工具
├── ViewModels/            数据管理
└── Views/                 界面（侧边栏 + 7 板块）
```
