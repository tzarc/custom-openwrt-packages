include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-policy-routing
PKG_VERSION:=0.2.0
PKG_RELEASE:=9

PKG_LICENSE:=UNLICENSE
PKG_MAINTAINER:=Nick Brassel <nick@tzarc.org>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-policy-routing
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI Support for Policy Routing
	PKGARCH:=all
	DEPENDS:=+policy-routing
endef

define Package/luci-app-policy-routing/description
	LuCI Support for Policy Routing.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-policy-routing/conffiles
endef

define Package/luci-app-policy-routing/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luci-controller-policy-routing.lua $(1)/usr/lib/lua/luci/controller/policy-routing.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luci-model-cbi-policy-routing.lua $(1)/usr/lib/lua/luci/model/cbi/policy-routing.lua
endef

define Package/luci-app-policy-routing/postinst
endef

define Package/luci-app-policy-routing/prerm
endef

$(eval $(call BuildPackage,luci-app-policy-routing))
