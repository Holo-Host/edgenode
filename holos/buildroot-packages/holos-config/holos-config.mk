HOLOS_CONFIG_VERSION = __HOLOS_VERSION__
HOLOS_CONFIG_SITE = ../../rust/holos-config
HOLOS_CONFIG_SITE_METHOD = local
HOLOS_CONFIG_LICENSE = MIT
HOLOS_CONFIG_LICENSE_FILE = LICENSE

define HOLOS_CONFIG_LOCK_FETCH
	$(HOST_DIR)/bin/cargo generate-lockfile --manifest-path=$(@D)/Cargo.toml
	$(HOST_DIR)/bin/cargo fetch --manifest-path=$(@D)/Cargo.toml --target=x86_64-unknown-linux-musl
endef

HOLOS_CONFIG_PRE_BUILD_HOOKS += HOLOS_CONFIG_LOCK_FETCH

define HOLOS_CONFIG_BUILD_CMDS
	$(HOST_DIR)/bin/cargo build --target=x86_64-unknown-linux-musl --release --manifest-path=$(@D)/Cargo.toml --offline
endef

define HOLOS_CONFIG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/target/x86_64-unknown-linux-musl/release/holos-config $(TARGET_DIR)/usr/bin/
endef

$(eval $(cargo-package))
