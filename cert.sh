#!/usr/bin/env bash
# Original code  from Brielle Bruns (https://source.sosdg.org/brielle/lets-encrypt-scripts/src/branch/master/gen-unifi-cert.sh)
# This is based off of version 1.7 from 4/2020 but last updated by me in 11/27/2021
# These changes expect you to be using Cloudflare and doing DNS-auth for LE cert validation.

# Location of LetsEncrypt binary we use.  Leave unset if you want to let it find automatically
# LEBINARY="/usr/src/letsencrypt/certbot-auto"

# Change to your UniFi Docker directory
unifiDir="/var/docker/unifi/data"

# Cloudflare DNS/auth ini file 
cfDNS="/var/docker/unifi/cloudflare.ini"

# docker container name for unifi 
containerName="unifi"

PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# change if you want t use the staging server 
SERVER="https://acme-v02.api.letsencrypt.org/directory"
#SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"

function usage() {
  echo "Usage: $0 -d <domain> [-e <email>] [-i]"
  echo "  -d <domain>: The domain name to use."
  echo "  -e <email>: Email address to use for certificate."
  echo "  -i: Insert only, use to force insertion of certificate."
}

while getopts "hid:e:" opt; do
  case $opt in
    i) onlyinsert="yes";;
    d) domains+=("$OPTARG");;
    e) email="$OPTARG";;
    h) usage
       exit;;
  esac
done

DEFAULTLEBINARY="/usr/bin/certbot /usr/bin/letsencrypt /usr/sbin/certbot
  /usr/sbin/letsencrypt /usr/local/bin/certbot /usr/local/sbin/certbot
  /usr/local/bin/letsencrypt /usr/local/sbin/letsencrypt
  /usr/src/letsencrypt/certbot-auto /usr/src/letsencrypt/letsencrypt-auto
  /usr/src/certbot/certbot-auto /usr/src/certbot/letsencrypt-auto
  /usr/src/certbot-master/certbot-auto /usr/src/certbot-master/letsencrypt-auto"

if [[ ! -v LEBINARY ]]; then
  for i in ${DEFAULTLEBINARY}; do
    if [[ -x ${i} ]]; then
      LEBINARY=${i}
      echo "Found LetsEncrypt/Certbot binary at ${LEBINARY}"
      break
    fi
  done
fi

# Command line options depending on New or Renew.
#NEWCERT="--renew-by-default certonly"
NEWCERT="--keep-until-expiring certonly"
RENEWCERT="-n renew"

# Check for required binaries
if [[ ! -x ${LEBINARY} ]]; then
  echo "Error: LetsEncrypt binary not found in ${LEBINARY} !"
  echo "You'll need to do one of the following:"
  echo "1) Change LEBINARY variable in this script"
  echo "2) Install LE manually or via your package manager and do #1"
  echo "3) Use the included get-letsencrypt.sh script to install it"
  exit 1
fi

if [[ ! -x $( which keytool ) ]]; then
  echo "Error: Java keytool binary not found."
  exit 1
fi

if [[ ! -x $( which openssl ) ]]; then
  echo "Error: OpenSSL binary not found."
  exit 1
fi

if [[ ! -z ${email} ]]; then
  email="--email ${email}"
else
  email=""
fi

shift $((OPTIND -1))
for val in "${domains[@]}"; do
        DOMAINS="${DOMAINS} -d ${val} "
done

MAINDOMAIN=${domains[0]}

if [[ -z ${MAINDOMAIN} ]]; then
  echo "Error: At least one -d argument is required"
  usage
  exit 1
fi

if [[ ${renew} == "yes" ]]; then
  LEOPTIONS="${RENEWCERT}"
else
  LEOPTIONS="${email} ${DOMAINS} ${NEWCERT}"
fi

if [[ ${onlyinsert} != "yes" ]]; then
  echo "Doing DNS-based certificate authentication to Cloudflare"
  #${LEBINARY} --break-my-certs --server ${SERVER} \
  ${LEBINARY} --server ${SERVER} \
              --agree-tos --dns-cloudflare --dns-cloudflare-credentials ${cfDNS} ${LEOPTIONS}
fi

if [[ ${onlyinsert} != "yes" ]] && md5sum -c "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem.md5" &>/dev/null; then
  echo "Cert has not changed, not updating controller."
  exit 0
else
  echo "Cert has changed or -i option was used, updating controller..."
  TEMPFILE=$(mktemp)
  ALLTEMPFILE=$(mktemp)

  md5sum "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem" > "/etc/letsencrypt/live/${MAINDOMAIN}/cert.pem.md5"
  cp ${unifiDir}/keystore ${unifiDir}/keystore.bak
  dockerContainerId=$(sudo docker container list | grep ${containerName} | awk '{print $1}')
  echo "Stopping container ${dockerContainerId}..."
  docker container stop ${dockerContainerId}
  sleep 10
  echo "Removing existing certificate from Unifi protected keystore..."
  keytool -delete -alias unifi -keystore ${unifiDir}/keystore -deststorepass aircontrolenterprise
  echo "Using openssl to prepare certificate..."
  # https://stackoverflow.com/a/40366230 - need to insert the key WITH the cert store, not separately. 
  cat /etc/letsencrypt/live/${MAINDOMAIN}/cert.pem /etc/letsencrypt/live/${MAINDOMAIN}/chain.pem /etc/letsencrypt/live/${MAINDOMAIN}/fullchain.pem > ${ALLTEMPFILE}
  openssl pkcs12 -export -in ${ALLTEMPFILE} -inkey /etc/letsencrypt/live/${MAINDOMAIN}/privkey.pem -out ${TEMPFILE} -name unifi -CAfile /etc/letsencrypt/live/${MAINDOMAIN}/chain.pem -caname root -passout pass:aircontrolenterprise
  echo "Inserting certificate into Unifi keystore..."
  keytool -importkeystore -deststorepass aircontrolenterprise -destkeypass aircontrolenterprise -destkeystore ${unifiDir}/keystore -srckeystore ${TEMPFILE} -srcstoretype PKCS12 -srcstorepass aircontrolenterprise -alias unifi

  sleep 2
  echo "Starting Unifi controller..."
  docker container start ${dockerContainerId}
  echo "Done!"
fi
