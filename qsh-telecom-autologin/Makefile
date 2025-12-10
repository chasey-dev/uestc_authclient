include $(TOPDIR)/rules.mk

PKG_NAME:=qsh-telecom-autologin
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/Aleksanaa/qsh-telecom-autologin.git
PKG_SOURCE_DATE:=2024-08-03
PKG_SOURCE_VERSION:=70f902793096b5f294fa7061a2e9030ffdf5ede7

# should define beforce including golang-package.mk
GO_PKG:=github.com/aleksanaa/qsh-telecom-autologin

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=UESTC CT Authentication Client
	DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/$(PKG_NAME)/description
	A command-line client for UESTC CT authentication.
endef

# GoPackage is for dev usage, copying src code to /usr/share/gocode/
# just use GoBinPackage to reduce package size
$(eval $(call GoBinPackage,$(PKG_NAME)))
$(eval $(call BuildPackage,$(PKG_NAME)))
