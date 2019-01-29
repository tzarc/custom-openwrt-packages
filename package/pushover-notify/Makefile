include $(TOPDIR)/rules.mk

PKG_NAME:=pushover-notify
PKG_VERSION:=0.2.0
PKG_RELEASE:=10

PKG_LICENSE:=UNLICENSE
PKG_MAINTAINER:=Nick Brassel <nick@tzarc.org>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/pushover-notify
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Pushover notifications
	PKGARCH:=all
	DEPENDS:=+curl
endef

define Package/pushover-notify/description
	Pushover notifications.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/pushover-notify/conffiles
/etc/config/pushover-notify
endef

define Package/pushover-notify/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./root/etc/config/pushover-notify $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/hotplug.d/dhcp
	$(INSTALL_DATA) ./root/etc/hotplug.d/dhcp/pushover-notify $(1)/etc/hotplug.d/dhcp/
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/pushover-notify $(1)/usr/bin/
endef

$(eval $(call BuildPackage,pushover-notify))
