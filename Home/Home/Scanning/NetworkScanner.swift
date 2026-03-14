import Foundation
import Network
import Darwin

struct ScanResult: Identifiable {
    let id = UUID()
    let ip: String
    var hostname: String?
    var pingMs: Int?
    let respondedAt: Date
}

@Observable
class NetworkScanner {
    var isScanning          = false
    var isCheckingPresence  = false
    var results: [ScanResult] = []
    var lastScannedAt: Date?
    var progress: Double    = 0

    /// Single source of truth for presence.
    /// Updated by both full scan() and quickPresenceCheck().
    var respondingIPs: Set<String> = []

    /// Latest round-trip time (ms) per IP. Updated by scan and presence checks.
    var pingTimes: [String: Int] = [:]

    // MARK: - Full network scan

    func scan(subnet: String) async {
        isScanning = true
        progress   = 0
        results    = []

        let ips = (1...254).map { "\(subnet).\($0)" }

        // Bonjour runs for the full scan duration in the background.
        async let mdnsFuture: [ScanResult] = NetworkScanner.mdnsScan()

        // ── Pass 1: wake devices + first ARP read ─────────────────────────────
        // UDP pokes trigger ARP at Layer 2. We wait 1500 ms for devices to wake
        // and respond, then ICMP-verify the candidates.
        await udpSweep(ips: ips, progressStart: 0.00, progressEnd: 0.22)
        try? await Task.sleep(for: .milliseconds(1500))
        progress = 0.28
        let arp1    = Set(NetworkScanner.readARPCache(subnet: subnet))
        let timed1  = await NetworkScanner.icmpVerifyWithRetry(ips: arp1)
        progress = 0.50

        // ── Pass 2: catch late-waking devices ────────────────────────────────
        // Some devices (phones in deep sleep, certain IoT) take >1500 ms to
        // respond to the first ARP. A second sweep + wait catches them.
        // Only IPs that didn't respond in pass 1 are re-verified (fast).
        await udpSweep(ips: ips, progressStart: 0.50, progressEnd: 0.65)
        try? await Task.sleep(for: .milliseconds(1500))
        progress = 0.70
        let arp2    = Set(NetworkScanner.readARPCache(subnet: subnet))
        let newIPs  = arp2.subtracting(Set(timed1.keys))
        let timed2  = newIPs.isEmpty ? [:] as [String: Int]
                                     : await NetworkScanner.icmpVerifyWithRetry(ips: newIPs)
        progress = 0.85

        // Merge both passes
        var allTimed = timed1
        for (ip, ms) in timed2 { allTimed[ip] = ms }

        for (ip, ms) in allTimed { insertSorted(ScanResult(ip: ip, pingMs: ms, respondedAt: Date())) }
        pingTimes.merge(allTimed) { _, new in new }

        // ARP-only fallback (ICMP socket unavailable)
        if results.isEmpty {
            for ip in arp1.union(arp2) { insertSorted(ScanResult(ip: ip, respondedAt: Date())) }
        }

        // TCP last resort
        if results.isEmpty {
            await withTaskGroup(of: ScanResult?.self) { group in
                for ip in ips { group.addTask { await NetworkScanner.tcpProbe(ip: ip) } }
                for await r in group { if let r { insertSorted(r) } }
            }
        }

        // Bonjour enrichment — collect whatever mDNS found during the scan
        let mdns = await mdnsFuture
        for r in mdns {
            if let idx = results.firstIndex(where: { $0.ip == r.ip }) {
                results[idx].hostname = r.hostname
            } else {
                insertSorted(r)
            }
        }

        respondingIPs = Set(results.map { $0.ip })
        lastScannedAt = Date()
        isScanning    = false
        progress      = 1.0
    }

    private func udpSweep(ips: [String], progressStart: Double, progressEnd: Double) async {
        let total = Double(ips.count)
        var done  = 0.0
        await withTaskGroup(of: Void.self) { group in
            for ip in ips { group.addTask { await NetworkScanner.udpPoke(ip) } }
            for await _ in group {
                done    += 1
                progress = progressStart + (done / total) * (progressEnd - progressStart)
            }
        }
    }

    // MARK: - Background presence check

    /// Probes only the IPs of assigned devices.
    ///
    /// Strategy — designed to handle iPhones in deep sleep:
    ///   Round 1 : ICMP only (catches already-awake devices in <100 ms)
    ///   Round 2 : UDP wake → 1.5 s wait → ICMP  (wakes sleeping phones)
    ///   Round 3 : ICMP again (last chance for slow wakers)
    ///
    /// Only devices that fail ALL three rounds are considered offline.
    func quickPresenceCheck(deviceIPs: [String], subnet: String) async {
        guard !isScanning, !isCheckingPresence, !deviceIPs.isEmpty else { return }
        isCheckingPresence = true
        defer { isCheckingPresence = false }

        var toCheck   = Set(deviceIPs)
        var confirmed = [String: Int]()

        // Round 1 — direct ICMP, fast
        let r1 = await NetworkScanner.icmpVerifyTimed(ips: toCheck)
        for (ip, ms) in r1 { confirmed[ip] = ms }
        toCheck = toCheck.subtracting(Set(r1.keys))

        if !toCheck.isEmpty {
            // Round 2 — UDP-wake the specific IPs first, then ICMP
            // This is the key fix for sleeping iPhones: a UDP packet triggers
            // the network stack to wake before we ICMP-probe.
            await withTaskGroup(of: Void.self) { group in
                for ip in toCheck { group.addTask { await NetworkScanner.udpPoke(ip) } }
                for await _ in group {}
            }
            try? await Task.sleep(for: .milliseconds(1500))
            let r2 = await NetworkScanner.icmpVerifyTimed(ips: toCheck)
            for (ip, ms) in r2 { confirmed[ip] = ms }
            toCheck = toCheck.subtracting(Set(r2.keys))
        }

        if !toCheck.isEmpty {
            // Round 3 — final ICMP attempt
            try? await Task.sleep(for: .seconds(1))
            let r3 = await NetworkScanner.icmpVerifyTimed(ips: toCheck)
            for (ip, ms) in r3 { confirmed[ip] = ms }
        }

        var updated = respondingIPs
        for ip in deviceIPs {
            if let ms = confirmed[ip] { updated.insert(ip); pingTimes[ip] = ms }
            else                      { updated.remove(ip) }
        }
        respondingIPs = updated
    }

    // MARK: - Helpers

    private func insertSorted(_ result: ScanResult) {
        let suffix = ipSuffix(result.ip)
        let idx = results.firstIndex { ipSuffix($0.ip) > suffix } ?? results.endIndex
        results.insert(result, at: idx)
    }

    // MARK: - Subnet detection

    nonisolated static func detectSubnet() -> String {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return "192.168.1" }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let current = ptr {
            let iface = current.pointee
            if String(cString: iface.ifa_name) == "en0",
               iface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(iface.ifa_addr, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &buf, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: buf)
                let p  = ip.split(separator: ".")
                if p.count == 4 { return "\(p[0]).\(p[1]).\(p[2])" }
            }
            ptr = current.pointee.ifa_next
        }
        return "192.168.1"
    }
}

// MARK: - ICMP ping

extension NetworkScanner {

    /// Full-scan verify: pings all IPs in parallel, retries once per device.
    /// Returns IP → pingMs for all devices that replied.
    nonisolated static func icmpVerifyWithRetry(ips: Set<String>) async -> [String: Int] {
        await withTaskGroup(of: (String, Int)?.self) { group in
            for ip in ips {
                group.addTask {
                    if let ms = icmpPing(ip: ip, timeoutMS: 800) { return (ip, ms) }
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let ms = icmpPing(ip: ip, timeoutMS: 800) else { return nil }
                    return (ip, ms)
                }
            }
            var result = [String: Int]()
            for await entry in group { if let (ip, ms) = entry { result[ip] = ms } }
            return result
        }
    }

    /// Single-round verify: one ping per device, all in parallel.
    /// Returns IP → pingMs for responding devices. Used in presence check rounds.
    nonisolated static func icmpVerifyTimed(ips: Set<String>) async -> [String: Int] {
        await withTaskGroup(of: (String, Int)?.self) { group in
            for ip in ips {
                group.addTask {
                    guard let ms = icmpPing(ip: ip, timeoutMS: 800) else { return nil }
                    return (ip, ms)
                }
            }
            var result = [String: Int]()
            for await entry in group { if let (ip, ms) = entry { result[ip] = ms } }
            return result
        }
    }

    /// Blocking ICMP echo. Returns round-trip time in ms, or nil if no reply.
    /// Uses SOCK_DGRAM (unprivileged on iOS — no entitlement needed).
    /// connect() filters recv() to the target IP, preventing cross-talk between
    /// the many concurrent pings.
    nonisolated private static func icmpPing(ip: String, timeoutMS: Int = 1500) -> Int? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var tv = timeval()
        tv.tv_sec  = timeoutMS / 1000
        tv.tv_usec = Int32((timeoutMS % 1000) * 1000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var dest = sockaddr_in()
        dest.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &dest.sin_addr) == 1 else { return nil }

        let connected = withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        guard connected else { return nil }

        let packet = buildICMPPacket()
        let t0     = DispatchTime.now()
        let sent   = packet.withUnsafeBytes { buf in Darwin.send(fd, buf.baseAddress!, buf.count, 0) }
        guard sent > 0 else { return nil }

        var recvBuf  = [UInt8](repeating: 0, count: 64)
        let received = recvBuf.withUnsafeMutableBytes { ptr in Darwin.recv(fd, ptr.baseAddress!, 64, 0) }
        guard received > 0 else { return nil }

        let ms = Int((DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000)
        return max(1, ms)
    }

    /// Builds a minimal ICMP echo request packet with a valid checksum.
    private static func buildICMPPacket() -> [UInt8] {
        var packet: [UInt8] = [
            8, 0,  // type = 8 (echo request), code = 0
            0, 0,  // checksum placeholder
            0, 1,  // identifier = 1 (big-endian; kernel may override for DGRAM)
            0, 1   // sequence   = 1 (big-endian)
        ]
        let cs   = icmpChecksum(packet)
        packet[2] = UInt8(cs >> 8)
        packet[3] = UInt8(cs & 0xff)
        return packet
    }

    /// RFC 792 ICMP checksum: one's complement of the one's complement sum
    /// of all 16-bit words in the data.
    private static func icmpChecksum(_ data: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < data.count {
            sum += UInt32(data[i]) << 8 | UInt32(data[i + 1])
            i   += 2
        }
        if i < data.count { sum += UInt32(data[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(truncatingIfNeeded: sum)
    }
}

// MARK: - UDP poke (Phase 1 — triggers ARP without waiting for response)

extension NetworkScanner {
    nonisolated private static func udpPoke(_ ip: String) async {
        guard let port = NWEndpoint.Port(rawValue: 9) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: port, using: .udp)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let box = VoidBox(cont)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: Data([0x00]), completion: .contentProcessed { _ in
                        conn.cancel(); box.resume()
                    })
                case .failed, .cancelled:
                    box.resume()
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                conn.cancel(); box.resume()
            }
        }
    }
}

// MARK: - ARP cache (fallback if ICMP unavailable)

extension NetworkScanner {
    nonisolated static func readARPCache(subnet: String) -> [String] {
        let NET_RT_FLAGS: Int32 = 2
        let RTF_LLINFO:   Int32 = 0x400
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, RTF_LLINFO]
        var needed = 0
        guard sysctl(&mib, 6, nil, &needed, nil, 0) == 0, needed > 0 else { return [] }

        var buf = [UInt8](repeating: 0, count: needed)
        guard sysctl(&mib, 6, &buf, &needed, nil, 0) == 0 else { return [] }

        var ips: [String] = []
        let rtMsghdrSize  = 92
        var offset        = 0

        while offset < needed {
            guard offset + rtMsghdrSize <= needed else { break }
            let msglen = buf.withUnsafeBytes { Int($0.load(fromByteOffset: offset, as: UInt16.self)) }
            guard msglen > 0 else { break }

            let sinOffset = offset + rtMsghdrSize
            if sinOffset + MemoryLayout<sockaddr_in>.size <= needed {
                let sin = buf.withUnsafeBytes { $0.load(fromByteOffset: sinOffset, as: sockaddr_in.self) }
                if sin.sin_family == UInt8(AF_INET) {
                    let sinLen    = max(16, Int((sin.sin_len + 7) & ~7))
                    let sdlOffset = sinOffset + sinLen
                    let hasMAC    = sdlOffset + 7 <= needed && buf[sdlOffset + 6] > 0
                    if hasMAC {
                        var addr  = sin.sin_addr
                        var ipBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        inet_ntop(AF_INET, &addr, &ipBuf, socklen_t(INET_ADDRSTRLEN))
                        let ip = String(cString: ipBuf)
                        if ip.hasPrefix(subnet + "."),
                           !ip.hasSuffix(".0"), !ip.hasSuffix(".255"), ip != "0.0.0.0" {
                            ips.append(ip)
                        }
                    }
                }
            }
            offset += msglen
        }
        return ips
    }
}

// MARK: - TCP probe (last resort)

extension NetworkScanner {
    nonisolated private static func tcpProbe(ip: String) async -> ScanResult? {
        let ports: [UInt16] = [80, 443, 22, 7000, 62078, 5000, 3689, 8080]
        return await withTaskGroup(of: Bool.self) { group in
            for port in ports { group.addTask { await probePort(ip: ip, port: port) } }
            for await alive in group {
                if alive { group.cancelAll(); return ScanResult(ip: ip, respondedAt: Date()) }
            }
            return nil
        }
    }

    nonisolated private static func probePort(ip: String, port: UInt16) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let conn = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
        let box  = BoolBox()
        return await withCheckedContinuation { cont in
            box.set(cont)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resume(true); conn.cancel()
                case .failed(let e):
                    if case .posix(let c) = e, c == .ECONNREFUSED || c == .ECONNRESET {
                        box.resume(true)
                    } else { box.resume(false) }
                    conn.cancel()
                case .waiting:
                    box.resume(false); conn.cancel()
                default: break
                }
            }
            conn.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                box.resume(false); conn.cancel()
            }
        }
    }
}

// MARK: - Bonjour / mDNS

extension NetworkScanner {
    nonisolated private static func mdnsScan() async -> [ScanResult] {
        let types = ["_airplay._tcp", "_raop._tcp", "_companion-link._tcp",
                     "_apple-mobdev2._tcp", "_ipp._tcp"]
        var byIP: [String: ScanResult] = [:]
        let lock = NSLock()
        await withTaskGroup(of: [ScanResult].self) { group in
            for t in types { group.addTask { await browseBonjour(t) } }
            for await found in group {
                lock.withLock { for r in found where byIP[r.ip] == nil { byIP[r.ip] = r } }
            }
        }
        return Array(byIP.values)
    }

    nonisolated private static func browseBonjour(_ type_: String) async -> [ScanResult] {
        var endpoints: [(NWEndpoint, String)] = []
        let lock    = NSLock()
        let browser = NWBrowser(for: .bonjour(type: type_, domain: "local."), using: .tcp)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            browser.browseResultsChangedHandler = { results, _ in
                lock.withLock {
                    for r in results {
                        if case .service(let name, _, _, _) = r.endpoint,
                           !endpoints.contains(where: { $0.1 == name }) {
                            endpoints.append((r.endpoint, name))
                        }
                    }
                }
            }
            browser.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: .seconds(4))
                browser.cancel()
                cont.resume()
            }
        }

        let collected = lock.withLock { endpoints }
        var found: [ScanResult] = []
        await withTaskGroup(of: ScanResult?.self) { group in
            for (ep, name) in collected {
                group.addTask {
                    guard let ip = await resolveServiceIP(ep) else { return nil }
                    return ScanResult(ip: ip, hostname: name, respondedAt: Date())
                }
            }
            for await r in group { if let r { found.append(r) } }
        }
        return found
    }

    nonisolated private static func resolveServiceIP(_ endpoint: NWEndpoint) async -> String? {
        let conn = NWConnection(to: endpoint, using: .tcp)
        let box  = StringBox()
        return await withCheckedContinuation { cont in
            box.set(cont)
            conn.pathUpdateHandler = { path in
                if let remote = path.remoteEndpoint,
                   case .hostPort(let host, _) = remote {
                    let s = "\(host)"
                    if s.contains(".") && !s.contains(":") { box.resume(s); conn.cancel() }
                }
            }
            conn.stateUpdateHandler = { state in
                if case .failed  = state { box.resume(nil); conn.cancel() }
                if case .waiting = state { box.resume(nil); conn.cancel() }
            }
            conn.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: .seconds(3))
                box.resume(nil); conn.cancel()
            }
        }
    }
}

// MARK: - Continuation boxes (thread-safe resume-once wrappers)

private func ipSuffix(_ ip: String) -> Int {
    Int(ip.split(separator: ".").last ?? "") ?? 0
}

private final class VoidBox: @unchecked Sendable {
    private var cont: CheckedContinuation<Void, Never>?
    private let lock = NSLock()
    init(_ c: CheckedContinuation<Void, Never>) { cont = c }
    func resume() { lock.withLock { cont?.resume(); cont = nil } }
}

private final class BoolBox: @unchecked Sendable {
    private var cont: CheckedContinuation<Bool, Never>?
    private let lock = NSLock()
    func set(_ c: CheckedContinuation<Bool, Never>) { lock.withLock { cont = c } }
    func resume(_ v: Bool) { lock.withLock { cont?.resume(returning: v); cont = nil } }
}

private final class StringBox: @unchecked Sendable {
    private var cont: CheckedContinuation<String?, Never>?
    private let lock = NSLock()
    func set(_ c: CheckedContinuation<String?, Never>) { lock.withLock { cont = c } }
    func resume(_ v: String?) { lock.withLock { cont?.resume(returning: v); cont = nil } }
}
