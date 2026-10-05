# 参考包分析 (Minis-iOS15.5_0_pbrc.ipa)

- 大小: 73,953,569 bytes (70.5 MB)
- MD5: acb9f155110c051ad6f94fc493e08558
- SHA256: 05d9b64d69265a11ebc80a6a5bef22851ff1e149afebb8c13b35d0cf660aed77
- MinimumOSVersion: 15.5
- 版本: 1.14 (build 1)
- Bundle ID: com.openminis.app
- 主二进制: 116 MB, arm64
- 包含 Share Extension: MinisShare.appex
- Frameworks: FFmpeg 相关

## 用户反馈
- 在 iOS 15.4 上点设置项有时卡住然后闪退
- 说明参考包在 15.5 上基本可用，但 15.4 有运行时兼容问题

## 对我们的启示
1. 目标定 15.4 (比参考包更低，要更小心)
2. 设置页面的闪退很可能是某个 iOS 16+ API 在运行时被调用
3. 尽量保持功能完整，不要过度裁剪
4. 参考包保留了 Share Extension，我们也应该保留
