import Foundation

let DEFAULT_FILE_MODE: FileMode = FileMode.S_IRUSR | FileMode.S_IWUSR | FileMode.S_IXUSR | FileMode.S_IRGRP | FileMode.S_IXGRP | FileMode.S_IROTH | FileMode.S_IXOTH

protocol BackupFile {
    var path: String { get }
    var domain: String { get }
    func toRecord() -> MbdbRecord
}

struct ConcreteFile: BackupFile {
    let path: String
    let domain: String
    let contents: Data?
    let srcPath: String?
    let owner: Int
    let group: Int
    let inode: UInt64?
    let mode: FileMode
    var hash: Data?
    var size: UInt64?

    init(path: String, domain: String, contents: Data? = nil, srcPath: String? = nil, owner: Int = 0, group: Int = 0, inode: UInt64? = nil, mode: FileMode = DEFAULT_FILE_MODE) {
        self.path = path
        self.domain = domain
        self.contents = contents
        self.srcPath = srcPath
        self.owner = owner
        self.group = group
        self.inode = inode
        self.mode = mode
        self.hash = nil
        self.size = nil
    }

    func readContents() -> Data {
        if let contents = self.contents {
            return contents
        }
        if let srcPath = self.srcPath {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: srcPath)) {
                return data
            }
        }
        return Data()
    }

    func toRecord() -> MbdbRecord {
        var mutableSelf = self
        let inode = mutableSelf.inode ?? UInt64.random(in: 0...UInt64.max)
        let currentTime = UInt32(Date().timeIntervalSince1970)
        if mutableSelf.hash == nil || mutableSelf.size == nil {
            let contents = mutableSelf.readContents()
            mutableSelf.hash = contents.sha1()
            mutableSelf.size = UInt64(contents.count)
        }

        return MbdbRecord(
            domain: domain,
            filename: path,
            link: "",
            hash: mutableSelf.hash ?? Data(),
            key: Data(),
            mode: mode | FileMode.S_IFREG,
            inode: inode,
            userId: UInt32(owner),
            groupId: UInt32(group),
            mtime: currentTime,
            atime: currentTime,
            ctime: currentTime,
            size: mutableSelf.size ?? 0,
            flags: 4,
            properties: []
        )
    }
}

struct Directory: BackupFile {
    let path: String
    let domain: String
    let owner: Int
    let group: Int
    let mode: FileMode

    init(path: String, domain: String, owner: Int = 0, group: Int = 0, mode: FileMode = DEFAULT_FILE_MODE) {
        self.path = path
        self.domain = domain
        self.owner = owner
        self.group = group
        self.mode = mode
    }

    func toRecord() -> MbdbRecord {
        let currentTime = UInt32(Date().timeIntervalSince1970)
        return MbdbRecord(
            domain: domain,
            filename: path,
            link: "",
            hash: Data(),
            key: Data(),
            mode: mode | FileMode.S_IFDIR,
            inode: 0,
            userId: UInt32(owner),
            groupId: UInt32(group),
            mtime: currentTime,
            atime: currentTime,
            ctime: currentTime,
            size: 0,
            flags: 4,
            properties: []
        )
    }
}

struct SymbolicLink: BackupFile {
    let path: String
    let domain: String
    let target: String
    let owner: Int
    let group: Int
    let inode: UInt64?
    let mode: FileMode

    init(path: String, domain: String, target: String, owner: Int = 0, group: Int = 0, inode: UInt64? = nil, mode: FileMode = DEFAULT_FILE_MODE) {
        self.path = path
        self.domain = domain
        self.target = target
        self.owner = owner
        self.group = group
        self.inode = inode
        self.mode = mode
    }

    func toRecord() -> MbdbRecord {
        let inode = self.inode ?? UInt64.random(in: 0...UInt64.max)
        let currentTime = UInt32(Date().timeIntervalSince1970)
        return MbdbRecord(
            domain: domain,
            filename: path,
            link: target,
            hash: Data(),
            key: Data(),
            mode: mode | FileMode.S_IFLNK,
            inode: inode,
            userId: UInt32(owner),
            groupId: UInt32(group),
            mtime: currentTime,
            atime: currentTime,
            ctime: currentTime,
            size: 0,
            flags: 4,
            properties: []
        )
    }
}

struct AppBundle {
    let identifier: String
    let path: String
    let containerContentClass: String
    let version: String

    init(identifier: String, path: String, containerContentClass: String, version: String = "804") {
        self.identifier = identifier
        self.path = path
        self.containerContentClass = containerContentClass
        self.version = version
    }
}

struct Backup {
    let files: [BackupFile]
    let apps: [AppBundle]

    init(files: [BackupFile], apps: [AppBundle] = []) {
        self.files = files
        self.apps = apps
    }

    func writeToDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        for file in files {
            if let concreteFile = file as? ConcreteFile {
                let hashKey = (concreteFile.domain + "-" + concreteFile.path).sha1().hexString()
                let fileURL = directory.appendingPathComponent(hashKey)
                let contents = concreteFile.readContents()
                try contents.write(to: fileURL)
            }
        }

        let mbdb = generateManifestDB()
        let mbdbURL = directory.appendingPathComponent("Manifest.mbdb")
        try mbdb.toBytes().write(to: mbdbURL)
        let statusURL = directory.appendingPathComponent("Status.plist")
        try generateStatus().write(to: statusURL)
        let manifestURL = directory.appendingPathComponent("Manifest.plist")
        try generateManifest().write(to: manifestURL)
        let infoURL = directory.appendingPathComponent("Info.plist")
        try PropertyListSerialization.data(fromPropertyList: [:], format: .binary, options: 0).write(to: infoURL)
    }

    private func generateManifestDB() -> Mbdb {
        let records = files.map { $0.toRecord() }
        return Mbdb(records: records)
    }

    private func generateStatus() -> Data {
        let statusDict: [String: Any] = [
            "BackupState": "new",
            "Date": Date(timeIntervalSince1970: 0),
            "IsFullBackup": false,
            "SnapshotState": "finished",
            "UUID": "00000000-0000-0000-0000-000000000000",
            "Version": "2.4"
        ]
        return try! PropertyListSerialization.data(fromPropertyList: statusDict, format: .binary, options: 0)
    }

    private func generateManifest() -> Data {
        var manifestDict: [String: Any] = [
            "BackupKeyBag": Data(base64Encoded: "VkVSUwAAAAQAAAAFVFlQRQAAAAQAAAABVVVJRAAAABDud41d1b9NBICR1BH9JfVtSE1D SwAAACgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAV1JBUAAAAA QAAAAAU0FMVAAAABRY5Ne2bthGQ5rf4O3gikep1e6tZUlURVIAAAAEAAAnEFVVSUQAAA QB7R8awiGR9aba1UuVahGPENMQVMAAAAEAAAAAVdSQVAAAAAEAAAAAktUWVAAAAAEAAA AAFdQS1kAAAAoN3kQAJloFg+ukEUY+v5P+dhc/Welw/oucsyS40UBh67ZHef5ZMk9UVV VSUQAAAAQgd0cg0hSTgaxR3PVUbcEkUNMQVMAAAAEAAAAAldSQVAAAAAEAAAAAktUWVAA AAAEAAAAAFdQS1kAAAAoMiQTXx0SJlyrGJzdKZQ+SfL124w+2Tf/3d1R2i9yNj9zZCHN JhnorVVVSUQAAAAQf7JFQiBOS12JDD7qwKNTSkNMQVMAAAAEAAAAA1dSQVAAAAAEAAAAA ktUWVAAAAAEAAAAAFdQS1kAAAAoSEelorROJA46ZUdwDHhMKiRguQyqHukotrxhjIfqi Z5ESBXX9txi51VVSUQAAAAQfF0G/837QLq01xH9+66vx0NMQVMAAAAEAAAABFdSQVAAA AAEAAAAAktUWVAAAAAEAAAAAFdQS1kAAAAol0BvFhd5bu4Hr75XqzNf4g0fMqZAie6OxI +x/pgm6Y95XW17N+ZIDVVVSUQAAAAQimkT2dp1QeadMu1KhJKNTUNMQVMAAAAEAAAABVd SQVAAAAAEAAAAA0tUWVAAAAAEAAAAAFdQS1kAAAAo2N2DZarQ6GPoWRgTiy/tdjKArOqT aH0tPSG9KLbIjGTOcLodhx23xFVVSUQAAAAQQV37JVZHQFiKpoNiGmT6+ENMQVMAAAAE AAAABldSQVAAAAAEAAAAA0tUWVAAAAAEAAAAAFdQS1kAAAAofe2QSvDC2cV7Etk4fSBb gqDx5ne/z1VHwmJ6NdVrTyWi80Sy869DM1VVSUQAAAAQFzkdH+VgSOmTj3yEcfWmMUNM QVMAAAAEAAAAB1dSQVAAAAAEAAAAA0tUWVAAAAAEAAAAAFdQS1kAAAAo7kLYPQ/DnHBE RGpaz37eyntIX/XzovsS0mpHW3SoHvrb9RBgOB+WblVVSUQAAAAQEBpgKOz9Tni8F9km SXd0sENMQVMAAAAEAAAACFdSQVAAAAAEAAAAA0tUWVAAAAAEAAAAAFdQS1kAAAAo5mxV oyNFgPMzphYhm1VG8Fhsin/xX+r6mCd9gByF5SxeolAIT/ICF1VVSUQAAAAQrfKB2uPSQ tWh82yx6w4BoUNMQVMAAAAEAAAACVdSQVAAAAAEAAAAA0tUWVAAAAAEAAAAAFdQS1kAAA Ao5iayZBwcRa1c1MMx7vh6lOYux3oDI/bdxFCW1WHCQR/Ub1MOv+QaYFVVSUQAAAAQiLX vK3qvQza/mea5inss/0NMQVMAAAAEAAAACldSQVAAAAAEAAAAA0tUWVAAAAAEAAAAAFdQ S1kAAAAoD2wHX7KriEe1E31z7SQ7/+AVymcpARMYnQgegtZD0Mq2U55uxwNr2FVVSUQAA AQQ/Q9feZxLS++qSe/a4emRRENMQVMAAAAEAAAAC1dSQVAAAAAEAAAAA0tUWVAAAAAEA AAAAFdQS1kAAAAocYda2jyYzzSKggRPw/qgh6QPESlkZedgDUKpTr4ZZ8FDgd7YoALY1g==")!,
            "Lockdown": [:],
            "SystemDomainsVersion": "20.0",
            "Version": "9.1"
        ]

        if !apps.isEmpty {
            var appsDict: [String: Any] = [:]
            for app in apps {
                let appInfo: [String: Any] = [
                    "CFBundleIdentifier": app.identifier,
                    "CFBundleVersion": app.version,
                    "ContainerContentClass": app.containerContentClass,
                    "Path": app.path
                ]
                appsDict[app.identifier] = appInfo
            }
            manifestDict["Applications"] = appsDict
        }

        return try! PropertyListSerialization.data(fromPropertyList: manifestDict, format: .binary, options: 0)
    }
}

extension String {
    func sha1() -> Data {
        guard let data = self.data(using: .utf8) else {
            return Data()
        }
        return data.sha1()
    }
}

extension Data {
    func sha1() -> Data {
        let len = UInt64(count) * 8
        var padded = self
        padded.append(0x80)
        
        while (padded.count * 8) % 512 != 448 {
            padded.append(0x00)
        }
        
        var length = len.bigEndian
        padded.append(contentsOf: Swift.withUnsafeBytes(of: length) { Array($0) } )
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0
        
        for chunkStart in stride(from: 0, to: padded.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 80)
            for i in 0..<16 {
                let wordStart = chunkStart + i * 4
                w[i] = UInt32(padded[wordStart]) << 24 |
                       UInt32(padded[wordStart + 1]) << 16 |
                       UInt32(padded[wordStart + 2]) << 8 |
                       UInt32(padded[wordStart + 3])
            }
            
            for i in 16..<80 {
                w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotatedLeft(by: 1)
            }

            var a = h0
            var b = h1
            var c = h2
            var d = h3
            var e = h4
            for i in 0..<80 {
                var f: UInt32
                var k: UInt32
                
                if i < 20 {
                    f = (b & c) | ((~b) & d)
                    k = 0x5A827999
                } else if i < 40 {
                    f = b ^ c ^ d
                    k = 0x6ED9EBA1
                } else if i < 60 {
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1BBCDC
                } else {
                    f = b ^ c ^ d
                    k = 0xCA62C1D6
                }
                
                let temp = (a.rotatedLeft(by: 5) &+ f &+ e &+ k &+ w[i]) & 0xFFFFFFFF
                e = d
                d = c
                c = b.rotatedLeft(by: 30)
                b = a
                a = temp
            }

            h0 = (h0 &+ a) & 0xFFFFFFFF
            h1 = (h1 &+ b) & 0xFFFFFFFF
            h2 = (h2 &+ c) & 0xFFFFFFFF
            h3 = (h3 &+ d) & 0xFFFFFFFF
            h4 = (h4 &+ e) & 0xFFFFFFFF
        }

        var result = Data()
        result.append(contentsOf: Swift.withUnsafeBytes(of: h0.bigEndian) { Array($0) })
        result.append(contentsOf: Swift.withUnsafeBytes(of: h1.bigEndian) { Array($0) })
        result.append(contentsOf: Swift.withUnsafeBytes(of: h2.bigEndian) { Array($0) })
        result.append(contentsOf: Swift.withUnsafeBytes(of: h3.bigEndian) { Array($0) })
        result.append(contentsOf: Swift.withUnsafeBytes(of: h4.bigEndian) { Array($0) })
        
        return result
    }
    
    func hexString() -> String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
}

extension UInt32 {
    func rotatedLeft(by bits: Int) -> UInt32 {
        return (self << bits) | (self >> (32 - bits))
    }
}