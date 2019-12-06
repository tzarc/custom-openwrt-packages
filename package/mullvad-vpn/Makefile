include $(TOPDIR)/rules.mk

PKG_NAME:=mullvad-vpn
PKG_VERSION:=0.0.1
PKG_RELEASE:=1

PKG_LICENSE:=UNLICENSE
PKG_MAINTAINER:=Nick Brassel <nick@tzarc.org>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/mullvad-vpn
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=VPN
	TITLE:=Mullvad VPN
	PKGARCH:=all
	DEPENDS:=+libuci-lua +luci-lib-nixio +openvpn-openssl +procd +ubus
endef

define Package/mullvad-vpn/description
	Mullvad VPN.
endef

define Build/Prepare
	mkdir -p ./root/usr/share/mullvad-vpn
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/mullvad-vpn/conffiles
/etc/config/mullvad-vpn
endef

define Package/mullvad-vpn/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./root/etc/config/* $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/* $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/* $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/usr/lib/mullvad-vpn
	$(INSTALL_DATA) ./root/usr/lib/mullvad-vpn/* $(1)/usr/lib/mullvad-vpn/
endef

define Package/mullvad-vpn/postinst
#!/bin/sh
# check if we are on real system
if [ -z "$${IPKG_INSTROOT}" ]; then
	echo "Enabling rc.d symlink for mullvad-vpn"
	/etc/init.d/mullvad-vpn enable

	while [ ! -z "$$(uci -q get ucitrack.@mullvad-vpn[-1] 2>/dev/null)" ] ; do
		uci -q delete ucitrack.@mullvad-vpn[-1]
	done

	uci -q batch <<-EOF >/dev/null
		add ucitrack mullvad-vpn
		set ucitrack.@mullvad-vpn[-1].init='mullvad-vpn'
		commit ucitrack
EOF
fi
exit 0
endef

define Package/mullvad-vpn/prerm
#!/bin/sh
# check if we are on real system
if [ -z "$${IPKG_INSTROOT}" ]; then
	echo "Stopping service and removing rc.d symlink for mullvad-vpn"
	/etc/init.d/mullvad-vpn stop || true
	/etc/init.d/mullvad-vpn disable

	while [ ! -z "$$(uci -q get ucitrack.@mullvad-vpn[-1] 2>/dev/null)" ] ; do
		uci -q delete ucitrack.@mullvad-vpn[-1]
	done
fi
exit 0
endef

$(eval $(call BuildPackage,mullvad-vpn))
