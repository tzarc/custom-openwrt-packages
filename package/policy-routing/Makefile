include $(TOPDIR)/rules.mk

PKG_NAME:=policy-routing
PKG_VERSION:=0.2.0
PKG_RELEASE:=45

PKG_LICENSE:=UNLICENSE
PKG_MAINTAINER:=Nick Brassel <nick@tzarc.org>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/policy-routing
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Policy routing
	PKGARCH:=all
	DEPENDS:=+dnsmasq-full +ip-full +iptables +ip6tables +ipset +libuci-lua +luci-lib-nixio +procd +unzip
endef

define Package/policy-routing/description
	Policy routing configuration.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/policy-routing/conffiles
/etc/config/policy-routing
endef

define Package/policy-routing/install
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./root/etc/config/* $(1)/etc/config/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/* $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/* $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_DATA) ./root/etc/hotplug.d/iface/* $(1)/etc/hotplug.d/iface/
	$(INSTALL_DIR) $(1)/usr/lib/policy-routing
	$(INSTALL_BIN) ./root/usr/lib/policy-routing/* $(1)/usr/lib/policy-routing/
endef

define Package/policy-routing/postinst
#!/bin/sh
# check if we are on real system
if [ -z "$${IPKG_INSTROOT}" ]; then
	echo "Enabling rc.d symlink for policy-routing"
	/etc/init.d/policy-routing enable

	while [ ! -z "$$(uci -q get ucitrack.@policy-routing[-1] 2>/dev/null)" ] ; do
		uci -q delete ucitrack.@policy-routing[-1]
	done

	while [ ! -z "$$(uci -q get ucitrack.@firewall[-1].affects 2>/dev/null | awk '/policy-routing/')" ] ; do
		uci -q del_list ucitrack.@firewall[-1].affects='policy-routing'
	done

	uci -q batch <<-EOF >/dev/null
		add ucitrack policy-routing
		set ucitrack.@policy-routing[-1].init='policy-routing'
		add_list ucitrack.@firewall[-1].affects='policy-routing'
		commit ucitrack
EOF
fi
exit 0
endef

define Package/policy-routing/prerm
#!/bin/sh
# check if we are on real system
if [ -z "$${IPKG_INSTROOT}" ]; then
	echo "Stopping service and removing rc.d symlink for policy-routing"
	/etc/init.d/policy-routing stop || true
	/etc/init.d/policy-routing disable

	while [ ! -z "$$(uci -q get ucitrack.@policy-routing[-1] 2>/dev/null)" ] ; do
		uci -q delete ucitrack.@policy-routing[-1]
	done

	while [ ! -z "$$(uci -q get ucitrack.@firewall[-1].affects 2>/dev/null | awk '/policy-routing/')" ] ; do
		uci -q del_list ucitrack.@firewall[-1].affects='policy-routing'
	done
fi
exit 0
endef


$(eval $(call BuildPackage,policy-routing))
