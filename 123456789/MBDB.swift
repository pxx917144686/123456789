import Foundation

// File mode bitfield
struct FileMode {
    let rawValue: UInt16
    
    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
    
    // File types
    static let S_IFMT   = FileMode(rawValue: 0o0170000)
    static let S_IFIFO  = FileMode(rawValue: 0o0010000)
    static let S_IFCHR  = FileMode(rawValue: 0o0020000)
    static let S_IFDIR  = FileMode(rawValue: 0o0040000)
    static let S_IFBLK  = FileMode(rawValue: 0o0060000)
    static let S_IFREG  = FileMode(rawValue: 0o0100000)
    static let S_IFLNK  = FileMode(rawValue: 0o0120000)
    static let S_IFSOCK = FileMode(rawValue: 0o0140000)

    // User permissions
    static let S_IRUSR  = FileMode(rawValue: 0o0000400)
    static let S_IWUSR  = FileMode(rawValue: 0o0000200)
    static let S_IXUSR  = FileMode(rawValue: 0o0000100)

    // Group permissions
    static let S_IRGRP  = FileMode(rawValue: 0o0000040)
    static let S_IWGRP  = FileMode(rawValue: 0o0000020)
    static let S_IXGRP  = FileMode(rawValue: 0o0000010)

    // Other permissions
    static let S_IROTH  = FileMode(rawValue: 0o0000004)
    static let S_IWOTH  = FileMode(rawValue: 0o0000002)
    static let S_IXOTH  = FileMode(rawValue: 0o0000001)

    // Special modes
    static let S_ISUID  = FileMode(rawValue: 0o0004000)
    static let S_ISGID  = FileMode(rawValue: 0o0002000)
    static let S_ISVTX  = FileMode(rawValue: 0o0001000)
}

// Allow bitwise operations on FileMode
extension FileMode: ExpressibleByIntegerLiteral {
    init(integerLiteral value: UInt16) {
        self.init(rawValue: value)
    }
}

func |(lhs: FileMode, rhs: FileMode) -> FileMode {
    return FileMode(rawValue: lhs.rawValue | rhs.rawValue)
}

func &(lhs: FileMode, rhs: FileMode) -> FileMode {
    return FileMode(rawValue: lhs.rawValue & rhs.rawValue)
}

struct MbdbRecord {
    let domain: String
    let filename: String
    let link: String
    let hash: Data
    let key: Data
    let mode: FileMode
    let inode: UInt64
    let userId: UInt32
    let groupId: UInt32
    let mtime: UInt32
    let atime: UInt32
    let ctime: UInt32
    let size: UInt64
    let flags: UInt8
    let properties: [(String, String)]

    static func fromStream(_ data: Data) -> [MbdbRecord] {
        var stream = data
        var records: [MbdbRecord] = []

        // Read header
        let header = stream.readBytes(count: 4)
        guard header == "mbdb".data(using: .utf8) else {
            return records
        }

        let version = stream.readBytes(count: 2)
        guard version == Data([0x05, 0x00]) else {
            return records
        }

        // Read records
        while stream.count > 0 {
            if let record = readRecord(from: &stream) {
                records.append(record)
            }
        }

        return records
    }

    private static func readRecord(from stream: inout Data) -> MbdbRecord? {
        guard let domain = stream.readString(),
              let filename = stream.readString(),
              let link = stream.readString(),
              let hash = stream.readData(),
              let key = stream.readData() else {
            return nil
        }

        let mode = FileMode(rawValue: stream.readUInt16())
        let inode = stream.readUInt64()
        let userId = stream.readUInt32()
        let groupId = stream.readUInt32()
        let mtime = stream.readUInt32()
        let atime = stream.readUInt32()
        let ctime = stream.readUInt32()
        let size = stream.readUInt64()
        let flags = stream.readUInt8()
        let propertiesCount = Int(stream.readUInt8())

        var properties: [(String, String)] = []
        for _ in 0..<propertiesCount {
            if let name = stream.readString(),
               let value = stream.readString() {
                properties.append((name, value))
            }
        }

        return MbdbRecord(
            domain: domain,
            filename: filename,
            link: link,
            hash: hash,
            key: key,
            mode: mode,
            inode: inode,
            userId: userId,
            groupId: groupId,
            mtime: mtime,
            atime: atime,
            ctime: ctime,
            size: size,
            flags: flags,
            properties: properties
        )
    }

    func toBytes() -> Data {
        var data = Data()

        data.writeString(domain)
        data.writeString(filename)
        data.writeString(link)
        data.writeData(hash)
        data.writeData(key)
        data.writeUInt16(mode.rawValue)
        data.writeUInt64(inode)
        data.writeUInt32(userId)
        data.writeUInt32(groupId)
        data.writeUInt32(mtime)
        data.writeUInt32(atime)
        data.writeUInt32(ctime)
        data.writeUInt64(size)
        data.writeUInt8(flags)
        data.writeUInt8(UInt8(properties.count))

        for (name, value) in properties {
            data.writeString(name)
            data.writeString(value)
        }

        return data
    }
}

struct Mbdb {
    let records: [MbdbRecord]

    func toBytes() -> Data {
        var data = Data()
        data.append("mbdb".data(using: .utf8)!)
        data.append(Data([0x05, 0x00]))

        for record in records {
            data.append(record.toBytes())
        }

        return data
    }
}

// Helper methods for Data
extension Data {
    mutating func readBytes(count: Int) -> Data? {
        guard count > 0 && count <= self.count else {
            return nil
        }

        let bytes = self.prefix(count)
        self.removeFirst(count)
        return bytes
    }

    mutating func readString() -> String? {
        let length = Int(readUInt16())
        if length == 0xFFFF {
            return ""
        }
        guard let data = readBytes(count: length) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    mutating func readData() -> Data? {
        let length = Int(readUInt16())
        if length == 0xFFFF {
            return Data()
        }
        return readBytes(count: length)
    }

    mutating func readUInt8() -> UInt8 {
        let value = self[0]
        self.removeFirst()
        return value
    }

    mutating func readUInt16() -> UInt16 {
        let value = UInt16(self[0]) << 8 | UInt16(self[1])
        self.removeFirst(2)
        return value
    }

    mutating func readUInt32() -> UInt32 {
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(self[i]) << UInt32((3 - i) * 8)
        }
        self.removeFirst(4)
        return value
    }

    mutating func readUInt64() -> UInt64 {
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(self[i]) << UInt64((7 - i) * 8)
        }
        self.removeFirst(8)
        return value
    }

    mutating func writeString(_ string: String) {
        if let data = string.data(using: .utf8) {
            writeUInt16(UInt16(data.count))
            append(data)
        } else {
            writeUInt16(0)
        }
    }

    mutating func writeData(_ data: Data) {
        writeUInt16(UInt16(data.count))
        append(data)
    }

    mutating func writeUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func writeUInt16(_ value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func writeUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func writeUInt64(_ value: UInt64) {
        append(UInt8((value >> 56) & 0xFF))
        append(UInt8((value >> 48) & 0xFF))
        append(UInt8((value >> 40) & 0xFF))
        append(UInt8((value >> 32) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}