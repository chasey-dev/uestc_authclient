include $(TOPDIR)/rules.mk

LUCI_TITLE:=清水河电信认证
LUCI_PKGARCH:=all
PKG_NAME:=luci-app-uestc_ct_authclient
PKG_VERSION:=1.2
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
    SECTION:=luci
    CATEGORY:=LuCI
    SUBMENU:=3. Applications
    TITLE:=$(LUCI_TITLE)
    PKGARCH:=$(LUCI_PKGARCH)
    DEPENDS:=+uestc_ct_authclient +jsonfilter
endef

define Package/$(PKG_NAME)/description
    LuCI App to manage uestc_ct_authclient and network monitoring.
endef

define Build/Compile
	@echo "Nothing to compile"
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/
	$(CP) ./luasrc/* $(1)/usr/lib/lua/luci/
	$(INSTALL_DIR) $(1)/usr/bin/
	$(INSTALL_BIN) ./files/usr/bin/uestc_ct_authclient_monitor.sh $(1)/usr/bin/
	$(INSTALL_BIN) ./files/usr/bin/uestc_ct_authclient_script.sh $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/init.d/
	$(INSTALL_BIN) ./root/etc/init.d/uestc_ct_authclient $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/etc/config/
	$(INSTALL_CONF) ./files/etc/config/uestc_ct_authclient $(1)/etc/config/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))

