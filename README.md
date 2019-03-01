# Installation

### OpenWrt 18.06.2 or later:

    opkg update
    opkg install uclient-fetch libustream-mbedtls ca-certificates
    echo -e -n 'untrusted comment: signify public key\nRWTJQ7zQrAjSK9ghgVcNRYNh2rVoHX24gg6awlYntnvfrnIzSy9GHDAn\n' > /tmp/tzarc_custom.pub && opkg-key add /tmp/tzarc_custom.pub
    ! grep -q 'tzarc_custom' /etc/opkg/customfeeds.conf && echo 'src/gz tzarc_custom https://opkg.tzarc.io' >> /etc/opkg/customfeeds.conf
    opkg update
    opkg install policy-routing
    opkg install luci-app-policy-routing

### ImageBuilder etc.:

Add the following to your repositories.conf:

    src/gz tzarc_custom https://opkg.tzarc.io

### Package sources for SDK:

https://github.com/tzarc/custom-openwrt-packages -- directory 'packages'

i.e.: https://github.com/tzarc/custom-openwrt-packages/tree/master/package
