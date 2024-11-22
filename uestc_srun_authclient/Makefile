include $(TOPDIR)/rules.mk

PKG_NAME:=uestc_srun_authclient
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/uestc_srun_authclient
	SECTION:=net
	CATEGORY:=Network
	TITLE:=uestc_srun_authclient
endef

define Package/uestc_srun_authclient/description
	A command-line client for uestc srun authentication.
endef

define Build/Prepare
	# Copy pre-built binary file.
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	# Do Nothing
	true
endef

define Build/InstallDev
	# Do Nothing
	true
endef

define Build/Install
	# Do Nothing
	true
endef

define Package/uestc_srun_authclient/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/uestc_srun_authclient $(1)/usr/bin/
endef

$(eval $(call BuildPackage,uestc_srun_authclient))
