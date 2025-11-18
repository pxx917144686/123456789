import Foundation

enum FileDomain: String {
    case exploit = "Library/Application Support/com.apple.icloud.searchpartyuseragentd"
    case regular = ""
}

struct FileToRestore {
    let path: String
    let domain: String
    let contents: String
    let owner: Int
    let group: Int
    let mode: Int
    let usesDomains: Bool

    init(path: String, domain: String, contents: String, owner: Int = 501, group: Int = 501, mode: Int = 0o644, usesDomains: Bool = false) {
        self.path = path
        self.domain = domain
        self.contents = contents
        self.owner = owner
        self.group = group
        self.mode = mode
        self.usesDomains = usesDomains
    }
}

enum ProtectedDomain {
    case Library
    case Media
    case System
    case ProtectedDomain

    static func fromPath(_ path: String) -> ProtectedDomain {
        if path.hasPrefix("Library/") {
            return .Library
        } else if path.hasPrefix("Media/") {
            return .Media
        } else if path.hasPrefix("System/") {
            return .System
        } else {
            return .ProtectedDomain
        }
    }

    var directory: String {
        switch self {
        case .Library:
            return "Library"
        case .Media:
            return "Media"
        case .System:
            return "System"
        case .ProtectedDomain:
            return "ProtectedDomain"
        }
    }

    var folderName: String {
        switch self {
        case .Library:
            return "Library"
        case .Media:
            return "MediaDomain"
        case .System:
            return "SystemDomain"
        case .ProtectedDomain:
            return "RootDomain"
        }
    }
}

func concatExploitFile(_ path: String, _ domain: FileDomain) -> String {
    return domain.rawValue + "/" + path
}

func concatRegularFile(_ path: String, _ domain: FileDomain) -> String {
    return path
}

func mergeDuplicates(_ files: [FileToRestore]) -> [FileToRestore] {
    var uniqueFiles: [FileToRestore] = []
    var seenPaths: Set<String> = []

    for file in files {
        let uniqueKey = file.domain + file.path
        if !seenPaths.contains(uniqueKey) {
            seenPaths.insert(uniqueKey)
            uniqueFiles.append(file)
        }
    }

    return uniqueFiles
}

func getDomainForPath(_ path: String, _ usesDomains: Bool) -> (String, String) {
    if usesDomains {
        if let slashIndex = path.firstIndex(of: "/") {
            let domain = String(path[..<slashIndex])
            let filePath = String(path[path.index(after: slashIndex)...])
            return (domain, filePath)
        } else {
            return ("", path)
        }
    } else {
        return ("", path)
    }
}

typealias ProgressCallback = (Int) -> Void

func restoreFiles(_ files: [FileToRestore], reboot: Bool = false, progress: ProgressCallback? = nil) throws {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("restore-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)

    defer {
        try? FileManager.default.removeItem(at: tempDir)
    }

    let backupResult = executeCommand("idevicebackup2", arguments: ["backup", "--full", "--system", tempDir.path])
    guard backupResult.success else {
        throw NSError(domain: "RestoreError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create empty backup: " + backupResult.error])
    }

    let manifestPath = tempDir.appendingPathComponent("Manifest.plist")
    var manifest = try PropertyListSerialization.propertyList(from: Data(contentsOf: manifestPath), options: [], format: nil) as! [String: Any]

    var allFiles: [BackupFile] = []

    for (index, file) in files.enumerated() {
        progress?(Int(Float(index) / Float(files.count) * 50))

        let (domain, filePath) = getDomainForPath(file.path, file.usesDomains)
        let protectedDomain = ProtectedDomain.fromPath(filePath)
        
        let dirPath = URL(fileURLWithPath: filePath).deletingLastPathComponent().path
        if !dirPath.isEmpty {
            let dirDomain: String
            if file.usesDomains {
                dirDomain = domain
            } else {
                dirDomain = protectedDomain.folderName
            }
            allFiles.append(Directory(path: dirPath, domain: dirDomain))
        }

        let fileDomain: String
        if file.usesDomains {
            fileDomain = domain
        } else {
            fileDomain = protectedDomain.folderName
        }

        let contents = file.contents.data(using: .utf8) ?? Data()
        let concreteFile = ConcreteFile(
            path: filePath,
            domain: fileDomain,
            contents: contents,
            owner: file.owner,
            group: file.group,
            mode: FileMode(rawValue: UInt16(file.mode))
        )
        allFiles.append(concreteFile)

        let crashDomain = file.usesDomains ? domain : "Library"
        let crashFileName = "CrashReporter/crash-" + UUID().uuidString + ".plist"
        let crashFileContents = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict><key>IncidentIdentifier</key><string>" + UUID().uuidString + "</string></dict></plist>"
        let crashFileData = crashFileContents.data(using: .utf8) ?? Data()
        let crashFileMode = FileMode.S_IRUSR | FileMode.S_IWUSR | FileMode.S_IRGRP | FileMode.S_IROTH
        
        let crashFile = ConcreteFile(
            path: crashFileName,
            domain: crashDomain,
            contents: crashFileData,
            owner: file.owner,
            group: file.group,
            mode: crashFileMode
        )
        allFiles.append(crashFile)
    }

    let uniqueFiles = mergeDuplicates(files)

    let backup = Backup(files: allFiles)

    try backup.writeToDirectory(tempDir)

    progress?(75)

    let restoreResult = executeCommand("idevicebackup2", arguments: ["restore", "--system", tempDir.path])
    guard restoreResult.success else {
        throw NSError(domain: "RestoreError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to restore backup: " + restoreResult.error])
    }

    if reboot {
        try rebootDevice()
    }

    progress?(100)
}

func executeCommand(_ command: String, arguments: [String]) -> (success: Bool, output: String, error: String) {
    let task = Process()
    let pipe = Pipe()
    let errorPipe = Pipe()

    task.launchPath = "/usr/bin/env"
    task.arguments = [command] + arguments
    task.standardOutput = pipe
    task.standardError = errorPipe

    task.launch()
    task.waitUntilExit()

    let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

    let output = String(data: outputData, encoding: .utf8) ?? ""
    let error = String(data: errorData, encoding: .utf8) ?? ""

    return (task.terminationStatus == 0, output, error)
}

func rebootDevice() throws {
    let rebootResult = executeCommand("idevicediagnostics", arguments: ["restart"])
    guard rebootResult.success else {
        throw NSError(domain: "RestoreError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to reboot device: " + rebootResult.error])
    }
}

@available(*, deprecated, message: "Use restoreFiles instead")
func restoreFile(_ path: String, _ contents: String, _ device: String? = nil) -> Bool {
    let files = [FileToRestore(path: path, domain: "", contents: contents)]
    do {
        try restoreFiles(files, reboot: false)
        return true
    } catch {
        return false
    }
}