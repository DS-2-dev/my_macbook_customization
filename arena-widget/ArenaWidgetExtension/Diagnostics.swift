import Darwin

enum Diagnostics {
    /// Peak physical footprint of this process — the number jetsam compares
    /// against the widget extension's memory limit.
    static func peakFootprintMB() -> Double {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? Double(usage.ri_lifetime_max_phys_footprint) / 1_048_576 : -1
    }
}
