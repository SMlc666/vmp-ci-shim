//! Demo crate exercised by the public `public_demo` job in `vmp-ci-shim`'s CI.

/// AArch64 NOP encoding (HINT #0 — `0xd503201f`).
pub const AARCH64_NOP: u32 = 0xd503201f;

/// Returns true if the four little-endian bytes encode the AArch64 NOP instruction.
pub fn is_aarch64_nop(bytes: &[u8; 4]) -> bool {
    u32::from_le_bytes(*bytes) == AARCH64_NOP
}

/// Returns the host CPU architecture as reported by the Rust standard library.
pub fn host_arch() -> &'static str {
    std::env::consts::ARCH
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nop_round_trip() {
        let bytes = AARCH64_NOP.to_le_bytes();
        assert!(is_aarch64_nop(&bytes));
    }

    #[test]
    fn non_nop_rejected() {
        // `mov x0, #0` encodes as 0xd2800000 — not a NOP.
        let bytes = 0xd2800000u32.to_le_bytes();
        assert!(!is_aarch64_nop(&bytes));
    }

    #[test]
    fn host_arch_returns_nonempty() {
        let arch = host_arch();
        assert!(!arch.is_empty(), "ARCH constant must be populated");
    }
}
