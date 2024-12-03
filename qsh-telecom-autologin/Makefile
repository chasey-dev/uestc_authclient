include $(TOPDIR)/rules.mk

PKG_NAME:=qsh-telecom-autologin
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_BUILD_DEPENDS:=golang

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/Aleksanaa/qsh-telecom-autologin.git
PKG_SOURCE_DATE:=2024-08-03
PKG_SOURCE_VERSION:=70f902793096b5f294fa7061a2e9030ffdf5ede7
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

GO_PKG:=github.com/aleksanaa/qsh-telecom-autologin

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=UESTC Telecom Authentication Client
endef

define Package/$(PKG_NAME)/description
	A command-line client for UESTC Telecom authentication.
endef

define Build/Configure
	$(call GoPackage/Build/Configure)
endef

define Build/Compile
	$(call GoPackage/Build/Compile)
endef

define Package/$(PKG_NAME)/install
	$(call GoPackage/Package/Install,$(1))
endef

$(eval $(call GoPackage,$(PKG_NAME)))
$(eval $(call BuildPackage,$(PKG_NAME)))
