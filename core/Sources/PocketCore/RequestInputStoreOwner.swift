import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class RequestInputOwnerLock: @unchecked Sendable {
    private final class WeakOwner {
        weak var value: RequestInputOwnerLock?
        init(_ value: RequestInputOwnerLock) { self.value = value }
    }

    private static let registryLock = NSLock()
    private static var registry: [String: WeakOwner] = [:]

    private let gate = NSLock()
    private var descriptor: Int32 = -1
    private var released = false
    let key: String
    private var ownsLock: Bool
    var isOwner: Bool {
        gate.lock(); defer { gate.unlock() }
        return ownsLock
    }

    private init(key: String, descriptor: Int32, isOwner: Bool) {
        self.key = key
        self.descriptor = descriptor
        self.ownsLock = isOwner
    }

    static func acquire(canonicalDirectory: URL) throws -> RequestInputOwnerLock {
        let key = canonicalDirectory.path
        registryLock.lock()
        if let existing = registry[key]?.value, existing.isOwner {
            registryLock.unlock()
            return RequestInputOwnerLock(key: key, descriptor: -1, isOwner: false)
        }
        registryLock.unlock()

        let lockURL = canonicalDirectory.appendingPathComponent("owner.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw RequestInputError.storage("could not open request input owner lock")
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            close(fd)
            if code == EWOULDBLOCK || code == EACCES {
                return RequestInputOwnerLock(key: key, descriptor: -1, isOwner: false)
            }
            throw RequestInputError.storage("could not lock request input owner lock")
        }

        let token = RequestInputOwnerLock(key: key, descriptor: fd, isOwner: true)
        registryLock.lock()
        if let existing = registry[key]?.value, existing.isOwner {
            registryLock.unlock()
            token.release()
            return RequestInputOwnerLock(key: key, descriptor: -1, isOwner: false)
        }
        registry[key] = WeakOwner(token)
        registryLock.unlock()
        return token
    }

    func release() {
        gate.lock()
        if released { gate.unlock(); return }
        released = true
        let wasOwner = ownsLock
        ownsLock = false
        let fd = descriptor
        descriptor = -1
        gate.unlock()

        if fd >= 0 {
            flock(fd, LOCK_UN)
            close(fd)
        }
        if wasOwner {
            Self.registryLock.lock()
            if Self.registry[key]?.value === self { Self.registry[key] = nil }
            Self.registryLock.unlock()
        }
    }

    deinit { release() }
}
