//
//  SkipSetupManager.swift
//  123456789
//
//  Created by pxx917144686 on 2025/11/17.
//

import Foundation

class SkipSetupManager {
    
    static let shared = SkipSetupManager()
    private let exploitManager = ExploitManager.shared
    
    // 创建一个临时目录用于存储跳过安装程序所需的文件
    private func createTempDirectory() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("skip_setup")
        do {
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.removeItem(at: tempDir)
            }
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            return tempDir
        } catch {
            print("创建临时目录失败: \(error)")
            return nil
        }
    }
    
    // 创建用于跳过安装程序的crash_on_purpose文件
    private func createCrashFile(in directory: URL) -> Bool {
        let crashFile = directory.appendingPathComponent("crash_on_purpose")
        let content = "故意崩溃以跳过设置"
        
        do {
            try content.write(to: crashFile, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("创建crash文件失败: \(error)")
            return false
        }
    }
    
    // 执行跳过安装程序功能
    func skipSetup() -> (Bool, String?) {
        // 检查设备是否已连接
        let (connected, connectionError) = exploitManager.checkDeviceConnection()
        if !connected {
            return (false, connectionError)
        }
        
        guard let uuid = exploitManager.getDeviceUUID() else {
            return (false, "无法获取设备UUID")
        }
        
        // 创建临时目录
        guard let tempDir = createTempDirectory() else {
            return (false, "无法创建临时目录")
        }
        
        defer {
            cleanupTempDirectory(tempDir)
        }
        
        // 创建crash文件
        guard createCrashFile(in: tempDir) else {
            return (false, "无法创建crash文件")
        }
        
        // 使用idevicebackup2创建包含crash文件的备份
        let backupCommand = "idevicebackup2"
        let backupArgs = ["-u", uuid, "backup", tempDir.path]
        
        let (backupSuccess, _, backupError) = exploitManager.executeCommand(backupCommand, arguments: backupArgs)
        if !backupSuccess {
            let errorMessage = backupError ?? "创建备份失败"
            return (false, errorMessage)
        }
        
        // 使用idevicebackup2恢复备份，触发跳过安装程序功能
        let restoreCommand = "idevicebackup2"
        let restoreArgs = ["-u", uuid, "restore", tempDir.path]
        
        let (restoreSuccess, restoreOutput, restoreError) = exploitManager.executeCommand(restoreCommand, arguments: restoreArgs)
        if !restoreSuccess {
            if restoreOutput.contains("crash_on_purpose") || restoreOutput.contains("Restore completed") || restoreOutput.contains("恢复完成") {
                return (true, nil)
            } else {
                let errorMessage = restoreError ?? "恢复备份失败"
                return (false, errorMessage)
            }
        }
        
        return (true, nil)
    }
    
    // 清理临时目录
    private func cleanupTempDirectory(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            print("清理临时目录失败: \(error)")
        }
    }
}