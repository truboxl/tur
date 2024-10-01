TERMUX_SUBPKG_DESCRIPTION="Rust nightly std for target x86_64-linux-android"
TERMUX_SUBPKG_DEPEND_ON_PARENT=false
TERMUX_SUBPKG_PLATFORM_INDEPENDENT=true
TERMUX_SUBPKG_BREAKS="rust-nightly-wasm32-unknown-unknown (<< 1.67.1-2023.02.27-nightly-0)"
TERMUX_SUBPKG_REPLACES="rust-nightly-wasm32-unknown-unknown (<< 1.67.1-2023.02.27-nightly-0)"
TERMUX_SUBPKG_INCLUDE="
opt/rust-nightly/lib/rustlib/x86_64-linux-android/lib/*.rlib
opt/rust-nightly/lib/rustlib/x86_64-linux-android/lib/libstd-*.so
"
