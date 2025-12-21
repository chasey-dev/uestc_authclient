include $(TOPDIR)/rules.mk

PKG_NAME:=go-nd-portal
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/chasey-dev/go-nd-portal.git
PKG_SOURCE_DATE:=2025-12-10
PKG_SOURCE_VERSION:=ae08bbcc05725257d879f49b86641ea9e455837a

PKG_BUILD_DEPENDS:=golang/host

# should define beforce including golang-package.mk
GO_PKG:=github.com/fumiama/go-nd-portal

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=UESTC Srun Authentication Client
	DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/$(PKG_NAME)/description
	A command-line client for UESTC Srun authentication.
endef

# GoPackage is for dev usage, copying src code to /usr/share/gocode/
# just use GoBinPackage to reduce package size
$(eval $(call GoBinPackage,$(PKG_NAME)))
$(eval $(call BuildPackage,$(PKG_NAME)))
