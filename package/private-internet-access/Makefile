include $(TOPDIR)/rules.mk

PKG_NAME:=private-internet-access
PKG_VERSION:=0.2.0
PKG_RELEASE:=34

PKG_LICENSE:=UNLICENSE
PKG_MAINTAINER:=Nick Brassel <nick@tzarc.org>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/private-internet-access
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=VPN
	TITLE:=Private Internet Access
	PKGARCH:=all
	DEPENDS:=+libuci-lua +luci-lib-nixio +openvpn-openssl +procd +ubus +unzip
endef

define Package/private-internet-access/description
	Private Internet Access.
endef

define Build/Prepare
	mkdir -p ./root/usr/share/pia
	/bin/sh ./root/usr/bin/update-pia-servers ./root/usr/share/pia
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/private-internet-access/conffiles
/etc/config/private-internet-access
endef

define Package/private-internet-access/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./root/etc/config/* $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/* $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/* $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/* $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/usr/share/pia
	$(INSTALL_DATA) ./root/usr/share/pia/* $(1)/usr/share/pia/
	$(INSTALL_DIR) $(1)/usr/lib/pia
	$(INSTALL_DATA) ./root/usr/lib/pia/* $(1)/usr/lib/pia/
endef

define Package/private-internet-access/postinst
#!/bin/sh
# check if we are on real system
if [ -z "$${IPKG_INSTROOT}" ]; then
	echo "Enabling rc.d symlink for PIA"
	/etc/init.d/private-internet-access enable

	while [ ! -z "$$(uci -q get ucitrack.@private-internet-access[-1] 2>/dev/null)" ] ; do
		uci -q delete ucitrack.@private-internet-access[-1]
	done

	uci -q batch <<-EOF >/dev/null
		add ucitrack private-internet-access
		set ucitrack.@private-internet-access[-1].init='private-internet-access'
		commit ucitrack
EOF
fi
exit 0
endef

define Package/private-internet-access/prerm
#!/bin/sh
# check if we are on real system
if [ -z "$${IPKG_INSTROOT}" ]; then
	echo "Stopping service and removing rc.d symlink for PIA"
	/etc/init.d/private-internet-access stop || true
	/etc/init.d/private-internet-access disable

	while [ ! -z "$$(uci -q get ucitrack.@private-internet-access[-1] 2>/dev/null)" ] ; do
		uci -q delete ucitrack.@private-internet-access[-1]
	done
fi
exit 0
endef

$(eval $(call BuildPackage,private-internet-access))
