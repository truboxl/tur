TERMUX_SUBPKG_DESCRIPTION="Rust nightly std for target aarch64-linux-android"
TERMUX_SUBPKG_DEPEND_ON_PARENT=false
TERMUX_SUBPKG_PLATFORM_INDEPENDENT=true
TERMUX_SUBPKG_BREAKS="rustc-nightly (<< 1.67.1-2023.02.27-nightly-0)"
TERMUX_SUBPKG_REPLACES="rustc-nightly (<< 1.67.1-2023.02.27-nightly-0)"
TERMUX_SUBPKG_INCLUDE="
opt/rust-nightly/lib/rustlib/aarch64-linux-android/lib/*.rlib
opt/rust-nightly/lib/rustlib/aarch64-linux-android/lib/libstd-*.so
"
