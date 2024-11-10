include $(TOPDIR)/rules.mk

PKG_NAME:=uestc_ct_authclient
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

define Package/uestc_ct_authclient
  SECTION:=net
  CATEGORY:=Network
  TITLE:=清水河电信认证客户端
endef

define Package/uestc_ct_authclient/description
  一个用于清水河电信认证的命令行客户端。
endef

define Build/Prepare
	# 创建构建目录并复制预编译的二进制文件
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/* $(PKG_BUILD_DIR)/
endef

define Build/Compile
	# 已经有预编译的二进制文件，无需编译步骤
	true
endef

define Build/InstallDev
	# 不执行任何操作，避免调用默认的 `make install`
	true
endef

define Build/Install
	# 不执行任何操作，避免调用默认的 `make install`
	true
endef

define Package/uestc_ct_authclient/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/uestc_ct_authclient $(1)/usr/bin/
endef

$(eval $(call BuildPackage,uestc_ct_authclient))

