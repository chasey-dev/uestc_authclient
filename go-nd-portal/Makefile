include $(TOPDIR)/rules.mk

PKG_NAME:=go-nd-portal
PKG_VERSION:=0.3.1-dirty-20250903
PKG_RELEASE:=1
PKG_BUILD_DEPENDS:=golang

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/chasey-dev/go-nd-portal.git
PKG_SOURCE_VERSION:=ae08bbcc05725257d879f49b86641ea9e455837a
PKG_SOURCE_DATE:=2025-12-10
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION)-$(PKG_SOURCE_VERSION).tar.gz

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

GO_PKG:=github.com/fumiama/go-nd-portal

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=UESTC Srun Authentication Client
endef

define Package/$(PKG_NAME)/description
	A command-line client for UESTC Srun authentication.
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
