include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-uestc_authclient
PKG_VERSION:=2.0
PKG_RELEASE:=1

LUCI_TITLE:=UESTC Authentication Client
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+uestc_ct_authclient +uestc_srun_authclient +jsonfilter

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
