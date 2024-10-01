TERMUX_SUBPKG_DESCRIPTION="Rust nightly source code files"
TERMUX_SUBPKG_DEPEND_ON_PARENT=false
TERMUX_SUBPKG_PLATFORM_INDEPENDENT=true
TERMUX_SUBPKG_BREAKS="rust-src-nightly (<< 1.67.1-2023.02.27-nightly-0)"
TERMUX_SUBPKG_REPLACES="rust-src-nightly (<< 1.67.1-2023.02.27-nightly-0)"
TERMUX_SUBPKG_INCLUDE="
opt/rust-nightly/lib/rustlib/src
"
