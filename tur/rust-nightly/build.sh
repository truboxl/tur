TERMUX_PKG_HOMEPAGE=https://www.rust-lang.org/
TERMUX_PKG_DESCRIPTION="Rust compiler and utilities (nightly version)"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_MAINTAINER="@termux-user-repository"
_VERSION="1.83.0"
_DATE="2024-10-02"
TERMUX_PKG_VERSION="1.83.0~2024.10.02"
TERMUX_PKG_SRCURL=https://static.rust-lang.org/dist/${_DATE}/rustc-nightly-src.tar.xz
TERMUX_PKG_SHA256=ca6051de8426585ef88d8594feb33e26607a5a9e1fb8ae02f473d52e0cb97015
_LLVM_MAJOR_VERSION=$(. $TERMUX_SCRIPTDIR/packages/libllvm/build.sh; echo $LLVM_MAJOR_VERSION)
_LLVM_MAJOR_VERSION_NEXT=$((_LLVM_MAJOR_VERSION + 1))
_LZMA_VERSION=$(. $TERMUX_SCRIPTDIR/packages/liblzma/build.sh; echo $TERMUX_PKG_VERSION)
TERMUX_PKG_DEPENDS="clang, libc++, libllvm (<< ${_LLVM_MAJOR_VERSION_NEXT}), lld, openssl, zlib"
TERMUX_PKG_BUILD_DEPENDS="wasi-libc"
TERMUX_PKG_BREAKS="rustc-nightly (<< 1.67.1-2023.02.27-nightly-0)"
TERMUX_PKG_REPLACES="rustc-nightly (<< 1.67.1-2023.02.27-nightly-0)"
TERMUX_PKG_NO_STATICSPLIT=true
TERMUX_PKG_AUTO_UPDATE=true
TERMUX_PKG_RM_AFTER_INSTALL="
bin/llc
bin/llvm-*
bin/opt
bin/sh
lib/liblzma.a
lib/liblzma.so
lib/liblzma.so.${_LZMA_VERSION}
lib/libtinfo.so.6
lib/libz.so
lib/libz.so.1
share/wasi-sysroot
"

termux_pkg_auto_update() {
	local version=$(curl https://releases.rs/ | grep Nightly | sed -ne "s/Nightly: \(.*\) (.*/\1/p" | sort | head -n1)
	local date=$(date +%Y-%m-%d)
	local latest_version="${version}~${date//-/.}"
	if [[ "${latest_version}" == "${TERMUX_PKG_VERSION}" ]]; then
		echo "INFO: No update needed. Already at version '${latest_version}'."
		return
	fi
	local current_date_epoch=$(date "+%s")
	local _COMMIT_DATE_epoch=$(date -d "${_DATE}" "+%s")
	local current_date_diff=$(((current_date_epoch-_COMMIT_DATE_epoch)/(60*60*24)))
	local cooldown_days=7
	if [[ "${current_date_diff}" -lt "${cooldown_days}" ]]; then
		cat <<- EOL
		INFO: Queuing updates since last push
		Cooldown (days) = ${cooldown_days}
		Days since      = ${current_date_diff}
		EOL
		return
	fi

	sed \
		-e "s/^_VERSION=.*/_VERSION=\"${version}\"/" \
		-e "s/^_DATE=.*/_DATE=\"${date}\"/" \
		-i "${TERMUX_PKG_BUILDER_DIR}/build.sh"

	termux_pkg_upgrade_version "${latest_version}"
}

termux_step_pre_configure() {
	termux_setup_cmake
	termux_setup_rust

	# default rust-std package to be installed
	TERMUX_PKG_DEPENDS+=", rust-nightly-std-${CARGO_TARGET_NAME/_/-}"

	local p="${TERMUX_PKG_BUILDER_DIR}/0001-set-TERMUX_PKG_API_LEVEL.diff"
	echo "Applying patch: $(basename "${p}")"
	sed "s|@TERMUX_PKG_API_LEVEL@|${TERMUX_PKG_API_LEVEL}|g" "${p}" \
		| patch --silent -p1

	export RUST_LIBDIR=$TERMUX_PKG_BUILDDIR/_lib
	mkdir -p $RUST_LIBDIR

	# we can't use -L$PREFIX/lib since it breaks things but we need to link against libLLVM-9.so
	ln -vfst "${RUST_LIBDIR}" \
		${TERMUX_PREFIX}/lib/libLLVM-${_LLVM_MAJOR_VERSION}.so

	# rust tries to find static library 'c++_shared'
	ln -vfs $TERMUX_STANDALONE_TOOLCHAIN/sysroot/usr/lib/$TERMUX_HOST_PLATFORM/libc++_static.a \
		$RUST_LIBDIR/libc++_shared.a

	# https://github.com/termux/termux-packages/issues/18379
	# NDK r26 multiple ld.lld: error: undefined symbol: __cxa_*
	ln -vfst "${RUST_LIBDIR}" "${TERMUX_PREFIX}"/lib/libc++_shared.so

	# https://github.com/termux/termux-packages/issues/11640
	# https://github.com/termux/termux-packages/issues/11658
	# The build system somehow tries to link binaries against a wrong libc,
	# leading to build failures for arm and runtime errors for others.
	# The following command is equivalent to
	#	ln -vfst $RUST_LIBDIR \
	#		$TERMUX_STANDALONE_TOOLCHAIN/sysroot/usr/lib/$TERMUX_HOST_PLATFORM/$TERMUX_PKG_API_LEVEL/lib{c,dl}.so
	# but written in a future-proof manner.
	ln -vfst $RUST_LIBDIR $(echo | $CC -x c - -Wl,-t -shared | grep '\.so$')

	# rust checks libs in PREFIX/lib. It then can't find libc.so and libdl.so because rust program doesn't
	# know where those are. Putting them temporarly in $PREFIX/lib prevents that failure
	# https://github.com/termux/termux-packages/issues/11427
	[[ "${TERMUX_ON_DEVICE_BUILD}" == "true" ]] && return
	mv $TERMUX_PREFIX/lib/liblzma.a{,.tmp} || :
	mv $TERMUX_PREFIX/lib/liblzma.so{,.tmp} || :
	mv $TERMUX_PREFIX/lib/liblzma.so.${_LZMA_VERSION}{,.tmp} || :
	mv $TERMUX_PREFIX/lib/libtinfo.so.6{,.tmp} || :
	mv $TERMUX_PREFIX/lib/libz.so.1{,.tmp} || :
	mv $TERMUX_PREFIX/lib/libz.so{,.tmp} || :
}

termux_step_configure() {
	echo "deb [arch=amd64] http://apt.llvm.org/noble/ llvm-toolchain-noble-18 main" | env -i PATH="$PATH" sudo tee /etc/apt/sources.list.d/apt-llvm-org-18.list > /dev/null
	env -i PATH="$PATH" sudo apt update
	env -i PATH="$PATH" sudo apt install -y clang-18 llvm-18-dev llvm-18-tools

	# it breaks building rust tools without doing this because it tries to find
	# ../lib from bin location:
	# this is about to get ugly but i have to make sure a rustc in a proper bin lib
	# configuration is used otherwise it fails a long time into the build...
	# like 30 to 40 + minutes ... so lets get it right

	# upstream tests build using versions N and N-1
	local BOOTSTRAP_VERSION=beta
	if [[ "${TERMUX_ON_DEVICE_BUILD}" == "false" ]]; then
		if ! rustup install "${BOOTSTRAP_VERSION}"; then
			echo "WARN: ${BOOTSTRAP_VERSION} is unavailable, fallback to stable version!"
			BOOTSTRAP_VERSION=stable
			rustup install "${BOOTSTRAP_VERSION}"
		fi
		rustup default "${BOOTSTRAP_VERSION}-x86_64-unknown-linux-gnu"
		export PATH="${HOME}/.rustup/toolchains/${BOOTSTRAP_VERSION}-x86_64-unknown-linux-gnu/bin:${PATH}"
	fi
	local RUSTC=$(command -v rustc)
	local CARGO=$(command -v cargo)

	if [[ "${TERMUX_ON_DEVICE_BUILD}" == "true" ]]; then
		local dir="${TERMUX_STANDALONE_TOOLCHAIN}/toolchains/llvm/prebuilt/linux-x86_64/bin"
		mkdir -p "${dir}"
		local target clang
		for target in aarch64-linux-android armv7a-linux-androideabi i686-linux-android x86_64-linux-android; do
			for clang in clang clang++; do
				ln -fsv "${TERMUX_PREFIX}/bin/clang" "${dir}/${target}${TERMUX_PKG_API_LEVEL}-${clang}"
			done
		done
	fi

	export RUST_PREFIX="${TERMUX_PREFIX}/opt/rust-nightly"
	mkdir -p "${RUST_PREFIX}"
	sed \
		-e "s|@RUST_PREFIX@|${RUST_PREFIX}|g" \
		-e "s|@TERMUX_PREFIX@|${TERMUX_PREFIX}|g" \
		-e "s|@TERMUX_STANDALONE_TOOLCHAIN@|${TERMUX_STANDALONE_TOOLCHAIN}|g" \
		-e "s|@CARGO_TARGET_NAME@|${CARGO_TARGET_NAME}|g" \
		-e "s|@RUSTC@|${RUSTC}|g" \
		-e "s|@CARGO@|${CARGO}|g" \
		"${TERMUX_PKG_BUILDER_DIR}"/config.toml > config.toml

	local env_host=$(printf $CARGO_TARGET_NAME | tr a-z A-Z | sed s/-/_/g)
	export ${env_host}_OPENSSL_DIR=$TERMUX_PREFIX
	export RUST_LIBDIR=$TERMUX_PKG_BUILDDIR/_lib
	export CARGO_TARGET_${env_host}_RUSTFLAGS="-L${RUST_LIBDIR}"

	# x86_64: __lttf2
	case "${TERMUX_ARCH}" in
	x86_64)
		export CARGO_TARGET_${env_host}_RUSTFLAGS+=" -C link-arg=$(${CC} -print-libgcc-file-name)" ;;
	esac

	# NDK r26
	export CARGO_TARGET_${env_host}_RUSTFLAGS+=" -C link-arg=-lc++_shared"

	# rust 1.79.0
	# note: ld.lld: error: undefined reference due to --no-allow-shlib-undefined: syncfs
	"${CC}" ${CPPFLAGS} -c "${TERMUX_PKG_BUILDER_DIR}/syncfs.c"
	"${AR}" rcu "${RUST_LIBDIR}/libsyncfs.a" syncfs.o
	export CARGO_TARGET_${env_host}_RUSTFLAGS+=" -C link-arg=-l:libsyncfs.a"

	export X86_64_UNKNOWN_LINUX_GNU_OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu
	export X86_64_UNKNOWN_LINUX_GNU_OPENSSL_INCLUDE_DIR=/usr/include
	export PKG_CONFIG_ALLOW_CROSS=1
	# for backtrace-sys
	export CC_x86_64_unknown_linux_gnu=gcc
	export CFLAGS_x86_64_unknown_linux_gnu="-O2"
	export RUST_BACKTRACE=full
}

termux_step_make() {
	:
}

termux_step_make_install() {
	unset CC CFLAGS CPP CPPFLAGS CXX CXXFLAGS LD LDFLAGS PKG_CONFIG RANLIB

	# needed to workaround build issue that only happens on x86_64
	# /home/runner/.termux-build/rust/build/build/bootstrap/debug/bootstrap: error while loading shared libraries: /lib/x86_64-linux-gnu/libc.so: invalid ELF header
	if [[ "${TERMUX_ON_DEVICE_BUILD}" == "false" ]] && [[ "${TERMUX_ARCH}" == "x86_64" ]]; then
		mv -v ${TERMUX_PREFIX}{,.tmp}
		${TERMUX_PKG_SRCDIR}/x.py build -j ${TERMUX_PKG_MAKE_PROCESSES} --host x86_64-unknown-linux-gnu --stage 1 cargo
		[[ -d "${TERMUX_PREFIX}" ]] && termux_error_exit "Contaminated PREFIX found:\n$(find ${TERMUX_PREFIX} | sort)"
		mv -v ${TERMUX_PREFIX}{.tmp,}
	fi

	# install causes on device build fail to continue
	# dist uses a lot of spaces on CI
	local job="install"
	[[ "${TERMUX_ON_DEVICE_BUILD}" == "true" ]] && job="dist"

	"${TERMUX_PKG_SRCDIR}/x.py" ${job} -j ${TERMUX_PKG_MAKE_PROCESSES} --stage 1

	# Not putting wasm32-* into config.toml
	# CI and on device (wasm32*):
	# error: could not document `std`
	"${TERMUX_PKG_SRCDIR}/x.py" install -j ${TERMUX_PKG_MAKE_PROCESSES} --target wasm32-unknown-unknown --stage 1 std
	[[ ! -e "${TERMUX_PREFIX}/share/wasi-sysroot" ]] && termux_error_exit "wasi-sysroot not found"
	"${TERMUX_PKG_SRCDIR}/x.py" install -j ${TERMUX_PKG_MAKE_PROCESSES} --target wasm32-wasi --stage 1 std
	"${TERMUX_PKG_SRCDIR}/x.py" install -j ${TERMUX_PKG_MAKE_PROCESSES} --target wasm32-wasip1 --stage 1 std
	"${TERMUX_PKG_SRCDIR}/x.py" install -j ${TERMUX_PKG_MAKE_PROCESSES} --target wasm32-wasip2 --stage 1 std

	"${TERMUX_PKG_SRCDIR}/x.py" dist -j ${TERMUX_PKG_MAKE_PROCESSES} rustc-dev

	# remove version suffix: beta, nightly
	local VERSION=nightly

	if [[ "${TERMUX_ON_DEVICE_BUILD}" == "true" ]]; then
		echo "WARN: Replacing on device rust! Caveat emptor!"
		rm -fr ${RUST_PREFIX}/lib/rustlib/${CARGO_TARGET_NAME}
		rm -fv $(find ${RUST_PREFIX}/lib -maxdepth 1 -type l -exec ls -l "{}" \; | grep rustlib | sed -e "s|.* ${RUST_PREFIX}/lib|${RUST_PREFIX}/lib|" -e "s| -> .*||")
	fi
	ls build/dist/*-${VERSION}*.tar.gz | xargs -P${TERMUX_PKG_MAKE_PROCESSES} -n1 -t -r tar -xf
	local tgz
	for tgz in $(ls build/dist/*-${VERSION}*.tar.gz); do
		echo "INFO: ${tgz}"
		./$(basename "${tgz}" | sed -e "s|.tar.gz$||")/install.sh --prefix=${RUST_PREFIX}
	done

	cd "$TERMUX_PREFIX/lib"
	rm -f libc.so libdl.so
	mv liblzma.a{.tmp,} || :
	mv liblzma.so{.tmp,} || :
	mv liblzma.so.${_LZMA_VERSION}{.tmp,} || :
	mv libtinfo.so.6{.tmp,} || :
	mv libz.so.1{.tmp,} || :
	mv libz.so{.tmp,} || :

	ln -vfs rustlib/${CARGO_TARGET_NAME}/lib/*.so ${RUST_PREFIX}/lib
	ln -vfs ${TERMUX_PREFIX}/bin/lld ${RUST_PREFIX}/bin/rust-lld

	cd "${RUST_PREFIX}/lib/rustlib"
	rm -fr \
		components \
		install.log \
		uninstall.sh \
		rust-installer-version \
		manifest-* \
		x86_64-unknown-linux-gnu

	cd "${RUST_PREFIX}/lib/rustlib/${CARGO_TARGET_NAME}/lib"
	echo "INFO: ${TERMUX_PKG_BUILDDIR}/rustlib-rlib.txt"
	ls *.rlib | tee "${TERMUX_PKG_BUILDDIR}/rustlib-rlib.txt"

	echo "INFO: ${TERMUX_PKG_BUILDDIR}/rustlib-so.txt"
	ls *.so | tee "${TERMUX_PKG_BUILDDIR}/rustlib-so.txt"

	echo "INFO: ${TERMUX_PKG_BUILDDIR}/rustc-dev-${VERSION}-${CARGO_TARGET_NAME}/rustc-dev/manifest.in"
	cat "${TERMUX_PKG_BUILDDIR}/rustc-dev-${VERSION}-${CARGO_TARGET_NAME}/rustc-dev/manifest.in" | tee "${TERMUX_PKG_BUILDDIR}/manifest.in"

	sed -e 's/^.....//' -i "${TERMUX_PKG_BUILDDIR}/manifest.in"
	local _included=$(cat "${TERMUX_PKG_BUILDDIR}/manifest.in")
	local _included_rlib=$(echo "${_included}" | grep '\.rlib$')
	local _included_so=$(echo "${_included}" | grep '\.so$')
	local _included=$(echo "${_included}" | grep -v "/rustc-src/")
	local _included=$(echo "${_included}" | grep -v '\.rlib$')
	local _included=$(echo "${_included}" | grep -v '\.so$')

	echo "INFO: _rlib"
	while IFS= read -r _rlib; do
		echo "${_rlib}"
		local _included_rlib=$(echo "${_included_rlib}" | grep -v "${_rlib}")
	done < "${TERMUX_PKG_BUILDDIR}/rustlib-rlib.txt"
	echo "INFO: _so"
	while IFS= read -r _so; do
		echo "${_so}"
		local _included_so=$(echo "${_included_so}" | grep -v "${_so}")
	done < "${TERMUX_PKG_BUILDDIR}/rustlib-so.txt"

	export _INCLUDED=$(echo -e "${_included}\n${_included_rlib}\n${_included_so}")
	echo -e "INFO: _INCLUDED:\n${_INCLUDED}"

	local _included_file
	while IFS= read -r _included_file; do
		if [[ -z "${_included_prefix-}" ]]; then
			local _included_prefix=$(echo -e "opt/rust-nightly/${_included_file}")
		else
			local _included_prefix=$(echo -e "${_included_prefix}\nopt/rust-nightly/${_included_file}")
		fi
	done < <(echo "${_INCLUDED}")
	export _INCLUDED="${_included_prefix}"
	echo -e "INFO: _INCLUDED:\n${_INCLUDED}"
}

termux_step_post_make_install() {
	mkdir -p "${TERMUX_PREFIX}/etc/profile.d"
	cat <<- EOF > "${TERMUX_PREFIX}/etc/profile.d/rust-nightly.sh"
	#!${TERMUX_PREFIX}/bin/sh"
	export PATH=${RUST_PREFIX}/bin:\$PATH"
	EOF
}

termux_step_create_debscripts() {
	cat <<- EOF > postinst
	#!${TERMUX_PREFIX}/bin/sh
	echo 'source \$PREFIX/etc/profile.d/rust-nightly.sh to use nightly'"
	echo 'or export RUSTC=\$PREFIX/opt/rust-nightly/bin/rustc'"
	EOF

	chmod u+x postinst
}
