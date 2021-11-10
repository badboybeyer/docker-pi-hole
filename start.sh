#!/bin/bash -e
# Dockerfile variables
export TAG
export ServerIP
export ServerIPv6
export PYTEST
export PHP_ENV_CONFIG
export PHP_ERROR_LOG
export HOSTNAME
export WEBLOGDIR
export DNS1
export DNS2
export DNSSEC
export DNS_BOGUS_PRIV
export DNS_FQDN_REQUIRED
export INTERFACE
export DNSMASQ_LISTENING_BEHAVIOUR="$DNSMASQ_LISTENING"
export IPv6
export WEB_PORT
export REV_SERVER
export REV_SERVER_DOMAIN
export REV_SERVER_TARGET
export REV_SERVER_CIDR
export CONDITIONAL_FORWARDING
export CONDITIONAL_FORWARDING_IP
export CONDITIONAL_FORWARDING_DOMAIN
export CONDITIONAL_FORWARDING_REVERSE
export TEMPERATUREUNIT
export ADMIN_EMAIL
export WEBUIBOXEDLAYOUT
export QUERY_LOGGING
export PIHOLE_DNS_
export DHCP_ACTIVE
export DHCP_START
export DHCP_END
export DHCP_ROUTER
export DHCP_LEASETIME
export PIHOLE_DOMAIN
export DHCP_IPv6
export DHCP_rapid_commit
export WEBTHEME
export CUSTOM_CACHE_SIZE

export adlistFile='/etc/pihole/adlists.list'

# If user has set QUERY_LOGGING Env Var, copy it out to _OVERRIDE, else it will get reset when we source the next two files
# Come back to it at the end of the file
[ -n "${QUERY_LOGGING}" ] && QUERY_LOGGING_OVERRIDE="${QUERY_LOGGING}"

# The below functions are all contained in bash_functions.sh
. /bash_functions.sh

# Ensure we have all functions available to update our configurations
. /opt/pihole/webpage.sh

# PH_TEST prevents the install from actually running (someone should rename that)
PH_TEST=true . "${PIHOLE_INSTALL}"

echo " ::: Starting docker specific checks & setup for docker pihole/pihole"

# TODO:
#if [ ! -f /.piholeFirstBoot ] ; then
#    echo " ::: Not first container startup so not running docker's setup, re-create container to run setup again"
#else
#    regular_setup_functions
#fi

fix_capabilities
load_web_password_secret
generate_password
validate_env || exit 1
prepare_configs

[ -n "${PIHOLE_INTERFACE}" ] && change_setting "PIHOLE_INTERFACE" "$PIHOLE_INTERFACE"
[ -n "${IPV4_ADDRESS}" ] && change_setting "IPV4_ADDRESS" "$IPV4_ADDRESS"
[ -n "${INSTALL_WEB_SERVER}" ] && change_setting "INSTALL_WEB_SERVER" "$INSTALL_WEB_SERVER"
[ -n "${INSTALL_WEB_INTERFACE}" ] && change_setting "INSTALL_WEB_INTERFACE" "$INSTALL_WEB_INTERFACE"
[ -n "${LIGHTTPD_ENABLED}" ] && change_setting "LIGHTTPD_ENABLED" "$LIGHTTPD_ENABLED"
[ -n "${ServerIP}" ] && changeFTLsetting "REPLY_ADDR4" "$ServerIP"
[ -n "${ServerIPv6}" ] && changeFTLsetting "REPLY_ADDR6" "$ServerIPv6"
[ -n "${DNS_BOGUS_PRIV}" ] && change_setting "DNS_BOGUS_PRIV" "$DNS_BOGUS_PRIV"
[ -n "${DNS_FQDN_REQUIRED}" ] && change_setting "DNS_FQDN_REQUIRED" "$DNS_FQDN_REQUIRED"
[ -n "${DNSSEC}" ] && change_setting "DNSSEC" "$DNSSEC"
[ -n "${REV_SERVER}" ] && change_setting "REV_SERVER" "$REV_SERVER"
[ -n "${REV_SERVER_DOMAIN}" ] && change_setting "REV_SERVER_DOMAIN" "$REV_SERVER_DOMAIN"
[ -n "${REV_SERVER_TARGET}" ] && change_setting "REV_SERVER_TARGET" "$REV_SERVER_TARGET"
[ -n "${REV_SERVER_CIDR}" ] && change_setting "REV_SERVER_CIDR" "$REV_SERVER_CIDR"

if [ -z "$REV_SERVER" ];then
    # If the REV_SERVER* variables are set, then there is no need to add these.
    # If it is not set, then adding these variables is fine, and they will be converted by the Pi-hole install script
    [ -n "${CONDITIONAL_FORWARDING}" ] && change_setting "CONDITIONAL_FORWARDING" "$CONDITIONAL_FORWARDING"
    [ -n "${CONDITIONAL_FORWARDING_IP}" ] && change_setting "CONDITIONAL_FORWARDING_IP" "$CONDITIONAL_FORWARDING_IP"
    [ -n "${CONDITIONAL_FORWARDING_DOMAIN}" ] && change_setting "CONDITIONAL_FORWARDING_DOMAIN" "$CONDITIONAL_FORWARDING_DOMAIN"
    [ -n "${CONDITIONAL_FORWARDING_REVERSE}" ] && change_setting "CONDITIONAL_FORWARDING_REVERSE" "$CONDITIONAL_FORWARDING_REVERSE"
fi

setupVarsDNS="$(grep 'PIHOLE_DNS_' /etc/pihole/setupVars.conf || true)"

dnsip="$(dig +short dnscrypt-proxy)"
echo "Configuring dnscrypt-proxy as DNS server: ${dnsip}#5053"
change_setting "PIHOLE_DNS_1" "$dnsip"

# remove extra dns variables
grep 'PIHOLE_DNS_' /etc/pihole/setupVars.conf | \
    grep -v PIHOLE_DNS_1 | \
    awk -F= '{print$1}' | \
    xargs -n1 delete_setting

# Parse the WEBTHEME variable, if it exists, and set the selected theme if it is one of the supported values.
# If an invalid theme name was supplied, setup WEBTHEME to use the default-light theme.
if [ -n "${WEBTHEME}" ]; then
    case "${WEBTHEME}" in
      "default-dark" | "default-darker" | "default-light")
        echo "Setting Web Theme based on WEBTHEME variable, using value ${WEBTHEME}"
        change_setting "WEBTHEME" "${WEBTHEME}"
        ;;
      *)
        echo "Invalid theme name supplied: ${WEBTHEME}, falling back to default-light."
        change_setting "WEBTHEME" "default-light"
        ;;
    esac
fi

[[ -n "${DHCP_ACTIVE}" && ${DHCP_ACTIVE} == "true" ]] && echo "Setting DHCP server" && setup_dhcp

setup_web_port "$WEB_PORT"
setup_web_password "$WEBPASSWORD"
setup_temp_unit "$TEMPERATUREUNIT"
setup_ui_layout "$WEBUIBOXEDLAYOUT"
setup_admin_email "$ADMIN_EMAIL"
setup_dnsmasq "$INTERFACE" "$DNSMASQ_LISTENING_BEHAVIOUR"
setup_php_env
setup_dnsmasq_hostnames "$ServerIP" "$ServerIPv6" "$HOSTNAME"
setup_ipv4_ipv6
setup_lighttpd_bind "$ServerIP"
setup_blocklists
test_configs

[ -f /.piholeFirstBoot ] && rm /.piholeFirstBoot

# Set QUERY_LOGGING value in setupVars to be that which the user has passed in as an ENV var (if they have)
[ -n "${QUERY_LOGGING_OVERRIDE}" ] && change_setting "QUERY_LOGGING" "$QUERY_LOGGING_OVERRIDE"

# Source setupVars.conf to get the true value of QUERY_LOGGING
. ${setupVars}

if [ ${QUERY_LOGGING} == "false" ]; then
  echo "::: Disabling Query Logging"
  pihole logging off
else
  # If it is anything other than false, set it to true
  change_setting "QUERY_LOGGING" "true"
  # Set pihole logging on for good measure
  echo "::: Enabling Query Logging"
  pihole logging on
fi

echo " ::: Docker start setup complete"
