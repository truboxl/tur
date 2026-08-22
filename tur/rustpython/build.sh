TERMUX_PKG_HOMEPAGE=https://rustpython.github.io/
TERMUX_PKG_DESCRIPTION="A Python Interpreter written in Rust"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux-user-repository"
TERMUX_PKG_VERSION="0.5.0"
TERMUX_PKG_SRCURL="https://github.com/RustPython/RustPython/archive/refs/tags/${TERMUX_PKG_VERSION}.tar.gz"
TERMUX_PKG_SHA256=6fa2bfd6d3a6c0ecb2aae216552ba24ad263546198c8a7b0c03c8111b6389d9c
TERMUX_PKG_DEPENDS="libffi"
TERMUX_PKG_BUILD_IN_SRC=true
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_UPDATE_TAG_TYPE="newest-tag"

termux_step_pre_configure() {
	termux_setup_rust
}

termux_step_make() {
	local build_args="--release"
	[[ "${TERMUX_DEBUG_BUILD}" == "true" ]] && build_args=""

	cargo build --jobs "${TERMUX_PKG_MAKE_PROCESSES}" --target "${CARGO_TARGET_NAME}" ${build_args}
}

termux_step_make_install() {
	local mode="release"
	[[ "${TERMUX_DEBUG_BUILD}" == "true" ]] && mode="debug"

	install -Dm700 -t "${TERMUX_PREFIX}/bin" "target/${CARGO_TARGET_NAME}/${mode}/rustpython"
}
