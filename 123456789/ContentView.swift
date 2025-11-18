// ContentView.swift
import SwiftUI
import AppKit
import Combine

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct ContentView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var systemColorScheme
    @StateObject private var manager = ExploitManager.shared
    
    @State private var deviceConnected = false
    @State private var deviceName: String?
    @State private var deviceModel: String?
    @State private var deviceModelName: String?
    @State private var iOSVersion: String?
    @State private var serialNumber: String?
    @State private var systemVersion: String?
    @State private var salesRegion: String?
    @State private var activationStatus: String?
    @State private var jailbreakStatus: String?

    @State private var disableLiquidGlass = false
    @State private var ignoreLiquidGlassBuildCheck = false
    @State private var statusMessage = ""
    @State private var statusCancellable: AnyCancellable?
    @State private var showApplyChangesAlert = false
    
    private let connectionTimer = Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            Color.primary.opacity(0.04)
                .background(
                    LinearGradient(
                        colors: [
                            Color(isLightTheme ? .white : Color(hex: "#0d0d1f")),
                            Color(isLightTheme ? .gray.opacity(0.1) : Color(hex: "#1a1a2e")),
                            Color(isLightTheme ? .gray.opacity(0.2) : Color(hex: "#16213e"))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Image(systemName: "circle.grid.3x3.fill")
                        .resizable()
                        .foregroundStyle((isLightTheme ? Color.black : Color.white).opacity(0.03))
                        .blendMode(.overlay)
                )
                .ignoresSafeArea()
            
            // 置顶显示的状态消息
            if !statusMessage.isEmpty {
                StatusNotification(message: statusMessage)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.top, 20) // 添加顶部边距
                    .zIndex(1000) // 确保通知显示在最顶层
            }
            
            // 主内容区
            VStack(spacing: 0) {
                HeaderSection(deviceConnected: deviceConnected)
                    .padding(.horizontal, 40)
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 32, pinnedViews: []) {
                        DeviceStatusHero(
                        isConnected: deviceConnected,
                        deviceModel: deviceModel,
                        deviceModelName: deviceModelName,
                        iOSVersion: iOSVersion,
                        serialNumber: serialNumber,
                        systemVersion: systemVersion,
                        salesRegion: salesRegion,
                        activationStatus: activationStatus,
                        jailbreakStatus: jailbreakStatus
                    )
                            .padding(.horizontal, 40)
                        
                        LiquidGlassControlCenter(
                            disableLiquidGlass: $disableLiquidGlass,
                            ignoreLiquidGlassBuildCheck: $ignoreLiquidGlassBuildCheck,
                            showApplyChangesAlert: $showApplyChangesAlert,
                            deviceConnected: deviceConnected
                        )
                        .padding(.horizontal, 40)
                        
                        Spacer(minLength: 60)

                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .onReceive(connectionTimer) { _ in
            Task {
                let (connected, _) = await manager.checkDeviceConnectionAsync()
                if connected != deviceConnected {
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.82)) {
                        deviceConnected = connected
                    }
                    await updateDeviceInfo()
                } else if connected {
                    await updateDeviceInfo()
                }
            }
        }
        .onAppear {
            Task {
                let (connected, _) = await manager.checkDeviceConnectionAsync()
                deviceConnected = connected
                await updateDeviceInfo()
            }
        }
        .alert("应用更改", isPresented: $showApplyChangesAlert) { 
            Button("取消", role: .cancel) { }
            Button("应用并重启", role: .destructive) { 
                Task {
                    await applyAllChanges(shouldRestart: true)
                }
            }
            Button("应用不重启") { 
                Task {
                    await applyAllChanges(shouldRestart: false)
                }
            }
        } message: { 
            Text("应用当前设置需要重启设备才能生效。您可以选择立即重启或稍后手动重启。")
        }
    }
    
    private func showStatus(_ text: String) {
        withAnimation(.easeInOut(duration: 0.3)) {
            statusMessage = text
        }
        statusCancellable?.cancel()
        statusCancellable = Timer.publish(every: 4, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation(.easeOut(duration: 0.6)) { statusMessage = "" }
            }
    }
    
    private var isLightTheme: Bool {
        if themeManager.themeMode == ThemeManager.ThemeMode.system {
            return systemColorScheme == .light
        }
        return themeManager.themeMode == ThemeManager.ThemeMode.light
    }
        
    private func updateDeviceInfo() async {
        guard deviceConnected else { return }
        Task {
            // 只获取一次设备信息，避免重复调用命令
            let (deviceInfo, error) = await manager.getDeviceInfoAsync()
            if let info = deviceInfo {
                deviceName = manager.getDeviceNameFromInfo(info)
                deviceModel = manager.getDeviceModelFromInfo(info)
                deviceModelName = manager.getDeviceModelNameFromInfo(info)
                iOSVersion = manager.getiOSVersionFromInfo(info)
                serialNumber = manager.getSerialNumberFromInfo(info)
                systemVersion = manager.getSystemVersionFromInfo(info)
                salesRegion = manager.getSalesRegionFromInfo(info)
                activationStatus = manager.getActivationStatusFromInfo(info)
                jailbreakStatus = await manager.getJailbreakStatusAsync()
            }
        }
    }
    
    private func applyAllChanges(shouldRestart: Bool) async {
        // 使用TaskGroup确保所有设置都应用完成
        await withTaskGroup(of: Void.self) { group in
            group.addTask { 
                // 应用禁用Liquid Glass设置
                await self.manager.setDisableLiquidGlass(self.disableLiquidGlass) { success, error in
                    if !success {
                        DispatchQueue.main.async {
                            self.showStatus(error ?? "禁用Liquid Glass设置失败")
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.showStatus("禁用Liquid Glass设置已应用")
                        }
                    }
                }
            }
            
            group.addTask { 
                // 应用强制启用所有APP设置
                await self.manager.setIgnoreLiquidGlassAppBuildCheck(self.ignoreLiquidGlassBuildCheck) { success, error in
                    if !success {
                        DispatchQueue.main.async {
                            self.showStatus(error ?? "强制启用所有APP设置失败")
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.showStatus("强制启用所有APP设置已应用")
                        }
                    }
                }
            }
        }
        
        // 根据用户选择决定是否重启设备
        if shouldRestart {
            DispatchQueue.main.async {
                showStatus("正在重启设备...")
                let (success, error) = self.manager.restartDevice()
                if !success {
                    self.showStatus(error ?? "重启失败")
                } else {
                    self.showStatus("设备正在重启...")
                }
            }
        } else {
            DispatchQueue.main.async {
                self.showStatus("设置已应用，设备将在下次重启时生效")
            }
        }
    }
}


struct HeaderSection: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var systemColorScheme
    let deviceConnected: Bool
    
    private var isLightTheme: Bool {
        if themeManager.themeMode == ThemeManager.ThemeMode.system {
            return systemColorScheme == .light
        }
        return themeManager.themeMode == ThemeManager.ThemeMode.light
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("娱乐一下~")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(isLightTheme ? Color.black : Color.white)
                    .shadow(color: (isLightTheme ? Color.black : Color.white).opacity(0.2), radius: 10, y: 5)
                
                Text("版本 v1.0.0")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle((isLightTheme ? Color.black : Color.white).opacity(0.7))
                Text("工具作者：pxx917144686")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle((isLightTheme ? Color.black : Color.white).opacity(0.7))
            }
            
            Spacer()
            
            ThemeSwitcher()
        }
    }
}


// 操作按钮组件
struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 80)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// 组件
struct ProgressRing: View {
    let progress: Double
    let size: CGFloat
    let strokeWidth: CGFloat
    let progressColor: Color
    let backgroundColor: Color
    let text: String
    let textColor: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(backgroundColor, lineWidth: strokeWidth)
                .frame(width: size, height: size)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(progressColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
            
            Text(text)
                .font(.system(size: size * 0.25, weight: .bold))
                .foregroundColor(textColor)
        }
    }
}


struct DeviceStatusHero: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var systemColorScheme
    let isConnected: Bool
    let deviceModel: String?
    let deviceModelName: String?
    let iOSVersion: String?
    let serialNumber: String?
    let systemVersion: String?
    let salesRegion: String?
    let activationStatus: String?
    let jailbreakStatus: String?
    
    private var isLightTheme: Bool {
        if themeManager.themeMode == ThemeManager.ThemeMode.system {
            return systemColorScheme == .light
        }
        return themeManager.themeMode == ThemeManager.ThemeMode.light
    }
        
    var body: some View {
        FrostedGlassCard {
            HStack(spacing: 32) {
                
                // 中间：系统信息卡片
                VStack(spacing: 24) {
                    // 设备连接状态
                    HStack(spacing: 12) {
                        Circle().fill(isConnected ? .green : .red).frame(width: 16, height: 16)
                        Text(isConnected ? "已成功连接到 iOS 设备" : "请通过 USB 连接并信任此电脑")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // 系统信息卡片
                    VStack(spacing: 16) {
                        HStack {
                            Text("系统版本")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(systemVersion ?? iOSVersion ?? "未知")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        
                        HStack {
                            Text("序列号")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(serialNumber ?? "未知")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                                                
                        HStack {
                            Text("型号")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(deviceModelName ?? "未知") (\(deviceModel ?? ""))")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        
                        HStack {
                            Text("销售地区")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(salesRegion ?? "未知")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        
                        HStack {
                            Text("激活状态")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(activationStatus ?? "未知")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        
                        HStack {
                            Text("越狱状态")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(jailbreakStatus ?? "未知")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)                    
                }                
            }
            .padding(40)
        }
    }
    
    // 设备信息项组件
    private func deviceInfoItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle((isLightTheme ? Color.black : Color.white).opacity(0.6))
            Text(value)
                .font(.subheadline)
                .foregroundStyle((isLightTheme ? Color.black : Color.white).opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((isLightTheme ? Color.black : Color.white).opacity(0.05))
        )
    }
}

// MARK: - Liquid Glass 控制
struct LiquidGlassControlCenter: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var systemColorScheme
    @Binding var disableLiquidGlass: Bool
    @Binding var ignoreLiquidGlassBuildCheck: Bool
    @Binding var showApplyChangesAlert: Bool
    let deviceConnected: Bool
    private let manager = ExploitManager.shared
    
    private var isLightTheme: Bool {
        if themeManager.themeMode == ThemeManager.ThemeMode.system {
            return systemColorScheme == .light
        }
        return themeManager.themeMode == ThemeManager.ThemeMode.light
    }
    
    var body: some View {
        FrostedGlassCard {
            VStack(alignment: .leading, spacing: 40) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("iOS26 Liquid Glass")
                        .font(.title.bold())
                        .foregroundStyle(isLightTheme ? Color.black : Color.white)
                    
                    Text("注意：是Apple官方 iOS26 Liquid Glass")
                        .font(.subheadline)
                        .foregroundStyle((isLightTheme ? Color.black : Color.white).opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "drop.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.cyan)
                        .symbolEffect(.pulse)
                }
                
                VStack(spacing: 0) {
                    VStack(spacing: 20) {
                        HStack {
                            Text("禁用-iPhone Liquid Glass")
                                .font(.title3.bold())
                                .foregroundStyle(isLightTheme ? Color.black : Color.white)
                            Spacer()
                            Toggle(isOn: $disableLiquidGlass) {}
                                .disabled(!deviceConnected)
                                .toggleStyle(.switch)
                                .tint(.red)
                                .onChange(of: disableLiquidGlass) { oldValue, newValue in
                                    if oldValue != newValue && deviceConnected {
                                        showApplyChangesAlert = true
                                    }
                                }
                        }

                        HStack {
                            Text("启用-iPhone Liquid Glass")
                                .font(.title3.bold())
                                .foregroundStyle(isLightTheme ? Color.black : Color.white)
                            Spacer()
                            Toggle(isOn: $ignoreLiquidGlassBuildCheck) {}
                                .disabled(!deviceConnected)
                                .toggleStyle(.switch)
                                .tint(.cyan)
                                .onChange(of: ignoreLiquidGlassBuildCheck) { oldValue, newValue in
                                    if oldValue != newValue && deviceConnected {
                                        showApplyChangesAlert = true
                                    }
                                }
                        }
                    }
                    .padding(20)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(48)
        }
    }
}

// MARK: - 玻璃卡片实现
struct FrostedGlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    
    var body: some View {
        content
            .padding(6)
            .background {
                RoundedRectangle(cornerRadius: 32)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 32)
                            .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                    }
                    .shadow(color: .primary.opacity(0.2), radius: 30, y: 15)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32))
    }
}

// MARK: - 开关模块实现
struct UltraToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let enabled: Bool
    let accent: Color
    let onToggleChange: () -> Void
    
    var body: some View {
        HStack {
            Text("\(title) - \(subtitle)")
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            
            Toggle(isOn: $isOn) {}
                .disabled(!enabled)
                .toggleStyle(.switch)
                .tint(accent)
                .onChange(of: isOn) { oldValue, newValue in
                    if oldValue != newValue && enabled {
                        onToggleChange()
                    }
                }
        }
        .padding(20)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }
}



struct StatusNotification: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.primary.opacity(0.3), lineWidth: 1))
            .shadow(radius: 20)
    }
}

// MARK: - 主题切换按钮
struct ThemeSwitcher: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var showMenu = false
    
    var body: some View {
        Button(action: { showMenu.toggle() }, label: {
            menuButtonLabel
        })
        .buttonStyle(.plain)
        .popover(isPresented: $showMenu) {
            themeMenuContent
        }
    }
    
    private var menuButtonLabel: some View {
        Image(systemName: currentIcon)
            .font(.title2)
            .foregroundStyle(.primary)
            .padding(18)
            .background(Circle().fill(.ultraThinMaterial))
    }
    
    private var themeMenuContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(ThemeManager.ThemeMode.allCases), id: \.self) { mode in
                Button {
                    themeManager.themeMode = mode
                    showMenu = false
                } label: {
                    themeMenuItem(for: mode)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }
    
    private func themeMenuItem(for mode: ThemeManager.ThemeMode) -> some View {
        HStack {
            Image(systemName: icon(for: mode))
                .foregroundStyle(.primary)
            Text(mode.rawValue)
                .foregroundStyle(.primary)
            Spacer()
            if themeManager.themeMode == mode {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(14)
    }
    
    private var currentIcon: String {
        switch themeManager.themeMode {
        case ThemeManager.ThemeMode.system: return "gearshape.fill"
        case ThemeManager.ThemeMode.light: return "sun.max.fill"
        case ThemeManager.ThemeMode.dark: return "moon.stars.fill"
        }
    }
    
    private func icon(for mode: ThemeManager.ThemeMode) -> String {
        switch mode {
        case .system: return "gearshape"
        case .light: return "sun.max"
        case .dark: return "moon.stars.fill"
        }
    }
}


// 这是APP界面窗口大小控制，默认1000x1500
#Preview {
    ContentView()
        .frame(width: 1000, height: 1500)
        .environmentObject(ThemeManager())
}