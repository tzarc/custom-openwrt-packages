include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-pushover-notify
PKG_VERSION:=0.2.1
PKG_RELEASE:=9

PKG_LICENSE:=UNLICENSE
PKG_MAINTAINER:=Nick Brassel <nick@tzarc.org>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-pushover-notify
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI Support for Pushover notifications
	PKGARCH:=all
	DEPENDS:=+pushover-notify
endef

define Package/luci-app-pushover-notify/description
	LuCI Support for Pushover notifications.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-pushover-notify/conffiles
endef

define Package/luci-app-pushover-notify/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luci-controller/pushover-notify.lua $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi
	$(INSTALL_DATA) ./luci-model-cbi/pushover-notify.lua $(1)/usr/lib/lua/luci/model/cbi
endef

$(eval $(call BuildPackage,luci-app-pushover-notify))
