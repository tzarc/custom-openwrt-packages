include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-private-internet-access
PKG_VERSION:=0.2.0
PKG_RELEASE:=11

PKG_LICENSE:=UNLICENSE
PKG_MAINTAINER:=Nick Brassel <nick@tzarc.org>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-private-internet-access
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI Support for Private Internet Access
	PKGARCH:=all
	DEPENDS:=+private-internet-access
endef

define Package/luci-app-private-internet-access/description
	LuCI Support for Private Internet Access.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-private-internet-access/conffiles
endef

define Package/luci-app-private-internet-access/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luci-controller-private-internet-access.lua $(1)/usr/lib/lua/luci/controller/private-internet-access.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luci-model-cbi-private-internet-access.lua $(1)/usr/lib/lua/luci/model/cbi/private-internet-access.lua
endef

define Package/luci-app-private-internet-access/postinst
endef

define Package/luci-app-private-internet-access/prerm
endef

$(eval $(call BuildPackage,luci-app-private-internet-access))
