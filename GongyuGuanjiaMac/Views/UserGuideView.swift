import SwiftUI

// MARK: - 使用说明 & 版本介绍

struct UserGuideView: View {
    @ObservedObject var manager: DataManager
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("使用说明")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("关闭") { onClose() }
                    .macPrimaryButton()
            }
            .padding(14)
            .background(Color.themeHeader)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 快速上手
                    VStack(alignment: .leading, spacing: 6) {
                        Text("快速上手")
                            .font(.system(size: 16, weight: .bold))
                        guideRow("1", "首次使用：点「设置」→「打开房源分享设置」，填写与 iOS 版相同的腾讯云配置和用户名，点「保存并验证」。")
                        guideRow("2", "新增房源：在「房源」页点「新增房源」，填写房号/房东/户型/租金，可选择实拍图与视频。保存后自动生成脱敏版分享页。")
                        guideRow("3", "同步互通：在「设置」→「云端同步」点「推送」或「拉取」，与 iOS 版数据互通（同一用户名）。")
                        guideRow("4", "选房链接：在「房源分享设置」→「公开选房链接」生成，微信打开即网页，自动列出未出租房源，支持按户型筛选。")
                        guideRow("5", "分享单套房源：房源详情→「分享」，选脱敏/完整版，复制链接或系统分享。")
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    // 数据与备份
                    VStack(alignment: .leading, spacing: 6) {
                        Text("数据与备份")
                            .font(.system(size: 16, weight: .bold))
                        guideRow("•", "数据保存在本机「应用支持/公寓管家Mac」，不在云端存敏感明文（密钥在系统钥匙串）。")
                        guideRow("•", "快速备份：经营数据 + 房源字段；全量备份：另含全部实拍媒体。")
                        guideRow("•", "自动备份每 6 小时一次，备份后自动上传云端（需已配置云端）。")
                        guideRow("•", "新装电脑后：先恢复快速备份，再「从云端拉取」房源，不会冲突乱码。")
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    // 版本介绍
                    VStack(alignment: .leading, spacing: 6) {
                        Text("版本介绍")
                            .font(.system(size: 16, weight: .bold))
                        Text("v1.0.0（当前版本）")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.themeAccent)
                        Text("""
                        Mac 版首发。与 iOS 版功能完全一致：
                        · 工作台：房源/成交/收租/支出统计卡片与快捷入口
                        · 房源：新增/编辑/搜索/筛选，网格与列表视图，实拍媒体管理，软删除回收站
                        · 成交：成交记录增删改，Excel 导入导出
                        · 收租：已租房源收租计划，租期到期提醒，系统本地通知
                        · 包租：物业台账与支出流水
                        · 汇总：月度佣金/杂费/支出/净结余统计
                        · 设置：云端同步、备份中心（快速/全量/云端）、房源分享设置（云配置/名片/二维码/水印/压缩上传/选房链接）、回收站、工具
                        · 分享：单房源脱敏/完整 H5 页，公开选房 H5（自动列出未出租房源+户型筛选+名片沉底）
                        · 与 iOS 版共用同一腾讯云 COS + 云函数后台，数据实时互通
                        """)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.themeText2)
                            .lineSpacing(4)
                    }
                    .padding(14)
                    .background(Color.themePanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.themeBorder))

                    Spacer(minLength: 20)
                }
                .padding(16)
            }
        }
        .frame(width: 620, height: 660)
        .background(Color.themeBg)
    }

    private func guideRow(_ badge: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(badge)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.themeAccent)
                .cornerRadius(5)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.themeText2)
                .lineSpacing(3)
        }
    }
}
