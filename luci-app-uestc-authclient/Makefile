include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-uestc-authclient
PKG_VERSION:=2.2
PKG_RELEASE:=4

LUCI_TITLE:=LuCI Support for UESTC Authentication Client
LUCI_DESCRIPTION:=LuCI App to manage uestc_ct/srun_authclient and network monitoring.
LUCI_DEPENDS:=+qsh-telecom-autologin +go-nd-portal +jsonfilter

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
