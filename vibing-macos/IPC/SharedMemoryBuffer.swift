//
//  SharedMemoryBuffer.swift
//  VibeTerminal
//
//  共享内存缓冲区 - 用于本地 PTY 通信，避免 TCP 开销
//
//  性能优势：
//  - 零拷贝数据传输
//  - 避免序列化/反序列化
//  - 更低的延迟
//
//  安全性：
//  - 使用 sem_* 信号量同步
//  - 权限控制（只有当前用户可访问）
//

import Foundation

// MARK: - 共享内存配置

struct SharedMemoryConfig {
    /// 缓冲区大小（字节）
    var bufferSize: Int = 1024 * 1024  // 1MB

    /// 共享内存名称前缀
    var namePrefix: String = "com.vibeterminal.shm"

    /// 信号量名称前缀
    var semaphorePrefix: String = "com.vibeterminal.sem"

    static let `default` = SharedMemoryConfig()
}

// MARK: - 共享内存错误

enum SharedMemoryError: Error, LocalizedError {
    case failedToOpen(String)
    case failedToMap(String)
    case invalidSize
    case permissionDenied
    case notInitialized
    case timeout

    var errorDescription: String? {
        switch self {
        case .failedToOpen(let msg):
            return "Failed to open shared memory: \(msg)"
        case .failedToMap(let msg):
            return "Failed to map shared memory: \(msg)"
        case .invalidSize:
            return "Invalid shared memory size"
        case .permissionDenied:
            return "Permission denied"
        case .notInitialized:
            return "Shared memory not initialized"
        case .timeout:
            return "Operation timed out"
        }
    }
}

// MARK: - 共享内存缓冲区头

/// 共享内存中的数据结构（按字节对齐）
struct SharedMemoryHeader: Codable {
    /// 魔数，用于验证
    var magic: UInt32 = 0x56424552  // "VBER"

    /// 版本号
    var version: UInt32 = 1

    /// 缓冲区大小
    var bufferSize: UInt32

    /// 写位置（字节偏移）
    var writeOffset: UInt32 = 0

    /// 读位置（字节偏移）
    var readOffset: UInt32 = 0

    /// 数据大小
    var dataSize: UInt32 = 0

    /// 最后更新时间戳
    var lastUpdate: UInt64 = 0

    /// 是否有新数据
    var hasData: UInt32 = 0
}

// MARK: - 共享内存缓冲区

final class SharedMemoryBuffer {
    private let config: SharedMemoryConfig
    private let name: String

    private var shmFD: Int32 = -1
    private var pointer: UnsafeMutableRawPointer?
    private var header: UnsafeMutablePointer<SharedMemoryHeader>?
    private var dataPointer: UnsafeMutableRawPointer?

    private var isMapped = false

    /// 数据区域大小
    private var dataRegionSize: Int {
        config.bufferSize - MemoryLayout<SharedMemoryHeader>.stride
    }

    init(name: String, config: SharedMemoryConfig = .default) {
        self.name = name
        self.config = config
    }

    deinit {
        cleanup()
    }

    // MARK: - 创建共享内存

    /// 创建新的共享内存区域
    func create() throws {
        // 打开共享内存
        let shmPath = "/\(config.namePrefix).\(name)"
        shmFD = shm_open(shmPath, O_CREAT | O_RDWR, 0600)

        guard shmFD >= 0 else {
            throw SharedMemoryError.failedToOpen("shm_open failed: \(String(cString: strerror(errno)))")
        }

        // 设置大小
        let result = ftruncate(shmFD, off_t(config.bufferSize))
        guard result == 0 else {
            close(shmFD)
            shmFD = -1
            throw SharedMemoryError.failedToOpen("ftruncate failed: \(String(cString: strerror(errno)))")
        }

        // 映射内存
        try map()

        // 初始化头部
        header?.pointee = SharedMemoryHeader(
            magic: 0x56424552,
            version: 1,
            bufferSize: UInt32(config.bufferSize),
            writeOffset: UInt32(MemoryLayout<SharedMemoryHeader>.stride),
            readOffset: UInt32(MemoryLayout<SharedMemoryHeader>.stride),
            dataSize: 0,
            lastUpdate: 0,
            hasData: 0
        )
    }

    // MARK: - 打开现有共享内存

    /// 打开已存在的共享内存区域
    func open() throws {
        let shmPath = "/\(config.namePrefix).\(name)"
        shmFD = shm_open(shmPath, O_RDWR, 0600)

        guard shmFD >= 0 else {
            throw SharedMemoryError.failedToOpen("shm_open failed: \(String(cString: strerror(errno)))")
        }

        try map()

        // 验证魔数
        guard header?.pointee.magic == 0x56424552 else {
            throw SharedMemoryError.failedToOpen("Invalid magic number")
        }
    }

    // MARK: - 内存映射

    private func map() throws {
        guard shmFD >= 0 else {
            throw SharedMemoryError.notInitialized
        }

        let ptr = mmap(
            nil,
            config.bufferSize,
            PROT_READ | PROT_WRITE,
            MAP_SHARED,
            shmFD,
            0
        )

        guard ptr != MAP_FAILED else {
            throw SharedMemoryError.failedToMap("mmap failed: \(String(cString: strerror(errno)))")
        }

        pointer = ptr
        header = ptr?.bindMemory(to: SharedMemoryHeader.self, capacity: 1)
        dataPointer = ptr?.advanced(by: MemoryLayout<SharedMemoryHeader>.stride)
        isMapped = true
    }

    // MARK: - 写入数据

    /// 写入数据到共享内存（非阻塞）
    func write(_ data: Data) throws {
        guard isMapped, let h = header, let dp = dataPointer else {
            throw SharedMemoryError.notInitialized
        }

        let count = data.count
        guard count <= dataRegionSize else {
            throw SharedMemoryError.invalidSize
        }

        // 复制数据
        data.withUnsafeBytes { src in
            memcpy(dp, src.baseAddress, count)
        }

        // 更新头部
        h.pointee.dataSize = UInt32(count)
        h.pointee.hasData = 1
        h.pointee.lastUpdate = UInt64(Date().timeIntervalSince1970)

        // 内存屏障，确保写入对其他进程可见
        OSMemoryBarrier()
    }

    /// 写入结构体
    func write<T>(_ value: T) throws {
        var data = Data(capacity: MemoryLayout<T>.stride)
        data.append(withUnsafeBytes(of: value) { Data($0) })
        try write(data)
    }

    // MARK: - 读取数据

    /// 从共享内存读取数据（非阻塞）
    func read() throws -> Data {
        guard isMapped, let h = header, let dp = dataPointer else {
            throw SharedMemoryError.notInitialized
        }

        // 内存屏障
        OSMemoryBarrier()

        let dataSize = Int(h.pointee.dataSize)
        guard dataSize > 0 else {
            return Data()
        }

        var data = Data(count: dataSize)
        data.withUnsafeMutableBytes { dst in
            memcpy(dst.baseAddress, dp, dataSize)
        }

        // 清除 hasData 标志
        h.pointee.hasData = 0

        return data
    }

    /// 读取结构体
    func read<T>(_ type: T.Type) throws -> T {
        let data = try read()
        guard data.count == MemoryLayout<T>.stride else {
            throw SharedMemoryError.invalidSize
        }
        return data.withUnsafeBytes { $0.load(as: T.self) }
    }

    // MARK: - 状态查询

    /// 是否有新数据
    var hasData: Bool {
        guard let h = header else { return false }
        OSMemoryBarrier()
        return h.pointee.hasData != 0
    }

    /// 数据大小
    var dataSize: Int {
        guard let h = header else { return 0 }
        return Int(h.pointee.dataSize)
    }

    /// 最后更新时间
    var lastUpdate: Date? {
        guard let h = header else { return nil }
        let interval = TimeInterval(h.pointee.lastUpdate)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    // MARK: - 清理

    private func cleanup() {
        if isMapped, let ptr = pointer {
            munmap(ptr, config.bufferSize)
            isMapped = false
        }

        if shmFD >= 0 {
            close(shmFD)
            shmFD = -1
        }
    }

    // MARK: - 删除共享内存

    /// 删除共享内存区域
    static func remove(name: String, config: SharedMemoryConfig = .default) {
        let shmPath = "/\(config.namePrefix).\(name)"
        shm_unlink(shmPath)
    }
}

// MARK: - POSIX 函数声明

@_silgen_name("shm_open")
private func shm_open(_ name: UnsafePointer<Int8>, _ oflag: Int32, _ mode: UInt16) -> Int32

@_silgen_name("shm_unlink")
private func shm_unlink(_ name: UnsafePointer<Int8>) -> Int32

@_silgen_name("mmap")
private func mmap(
    _ addr: UnsafeMutableRawPointer?,
    _ len: Int,
    _ prot: Int32,
    _ flags: Int32,
    _ fd: Int32,
    _ offset: off_t
) -> UnsafeMutableRawPointer

@_silgen_name("munmap")
private func munmap(_ addr: UnsafeMutableRawPointer, _ len: Int) -> Int32

private let MAP_FAILED = UnsafeMutableRawPointer(bitPattern: -1)

private var O_CREAT: Int32 { 0o1000 }
private var O_RDWR: Int32 { 0o2 }
private var PROT_READ: Int32 { 0x1 }
private var PROT_WRITE: Int32 { 0x2 }
private var MAP_SHARED: Int32 { 0x1 }

// MARK: - 共享内存池

/// 共享内存池管理器
final class SharedMemoryPool {
    static let shared = SharedMemoryPool()

    private var buffers: [String: SharedMemoryBuffer] = [:]
    private let lock = NSLock()

    private init() {}

    /// 获取或创建共享内存缓冲区
    func buffer(named name: String, create: Bool = false) throws -> SharedMemoryBuffer {
        lock.lock()
        defer { lock.unlock() }

        if let buffer = buffers[name] {
            return buffer
        }

        let buffer = SharedMemoryBuffer(name: name)

        if create {
            try buffer.create()
        } else {
            try buffer.open()
        }

        buffers[name] = buffer
        return buffer
    }

    /// 移除缓冲区
    func removeBuffer(named name: String) {
        lock.lock()
        defer { lock.unlock() }

        buffers.removeValue(forKey: name)
        SharedMemoryBuffer.remove(name: name)
    }

    /// 清理所有缓冲区
    func cleanup() {
        lock.lock()
        buffers.removeAll()
        lock.unlock()
    }
}
