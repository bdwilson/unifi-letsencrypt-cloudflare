# unifi-letsencrypt-cloudflare
<p>

This script is to update your Unifi controller with a legitimate certificate
from letsencrypt so that you can put your controller behind Cloudflare
teams/argo tunnel. No matter what I did to try and get cloudflared to use a
self-signed cert, it would never work. The benefit of using DNS-based
authentication for Lets encrypt is your host doesn't have to be exposed to the
internet for you to get your certificate. In my situation, my controller is
behind a Cloudflare tunnel, thus isn't not accessible/routable to get a
certificate via the standard way via a temporary host on port 80. 

# Requirements
* Unifi controller docker container - I use [this one](https://hub.docker.com/r/jacobalberty/unifi/) from @jacobalberty
* A Cloudflare account for your domain that you wish to get a cert from (you'll
need to get an API key as well). You will need to make sure your API key has
edit permissions to your [DNS
zone](https://developers.cloudflare.com/api/tokens/create). 
* certbot utility. 

# Optional 
Put your Unifi controller behind an argo tunnel. You can read about how to do
this [here]((https://omar2cloud.github.io/cloudflare/cloudflared/cloudflare/).I
also have a [docker container for
cloudflared](https://github.com/bdwilson/cloudflared-docker) that can help with
this.

# Installation
* Edit cert.sh to add the data directory for your Unifi data files (where your
keystore file is for certificates)
* Create your cloudflare.ini file to authenticate to add the dns records for
your request.
* Update your unifi docker name

# Usage
To request a new certificate or process a renewal if due.  You can run this
from cron once a week and it will only update unifi if the cert has changed.
* `sudo ./cert.sh -e email@mydomain.com -d unifi.mydomain.com`

To update an already existing certificate into Unifi. 
* `sudo ./cert.sh -i -d unifi.mydomain.com`

Inspired by
[Brielle's](https://source.sosdg.org/brielle/lets-encrypt-scripts/src/branch/master/gen-unifi-cert.sh) unifi update script.
