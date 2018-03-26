#!/bin/bash

DAYS_BEFORE_EXPIRE=30

[ -f '/opt/letsencrypt/settings'  ] && source '/opt/letsencrypt/settings' || { echo "No settings available" ; exit 3 ; }
[ -f '/root/validation.sh'  ] && source '/root/validation.sh' || { echo "No validation library available" ; exit 3 ; }

validateExtIP
validateDNSSettings

TIME_TO_WAIT=$(($RANDOM%3600));
sleep $TIME_TO_WAIT;

auto_update_url=$1
jerror_url=$(awk -F "/" '{ print $1"//"$2$3"/1.0/environment/jerror/rest"}' <<< $auto_update_url )

seconds_before_expire=$(( $DAYS_BEFORE_EXPIRE * 24 * 60 * 60 ));

WGET=$(which wget);
GIT=$(which git);
BASE_REPO_URL="https://github.com/jelastic-jps/lets-encrypt"
RAW_REPO_SCRIPS_URL="https://raw.githubusercontent.com/jelastic-jps/lets-encrypt/multiple-ip-bug/scripts/"


function validateLatestVersion(){
   local revision_state_path="/root/.lerevision";
   local latest_revision=$($GIT ls-remote $BASE_REPO_URL | grep master | awk '{ print $1}');
   [ -f "$revision_state_path" ] && current_revision=$(cat $revision_state_path);
   [ "$latest_revision" != "$current_revision" ] && {
        $WGET $RAW_REPO_SCRIPS_URL/auto-update-ssl-cert.sh -O /tmp/auto-update-ssl-cert.sh
        $WGET $RAW_REPO_SCRIPS_URL/install-le.sh -O /tmp/install-le.sh
        $WGET $RAW_REPO_SCRIPS_URL/validation.sh -O /tmp/validation.sh
        $WGET $RAW_REPO_SCRIPS_URL/generate-ssl-cert.sh -O /tmp/generate-ssl-cert.sh
        [  -s /tmp/auto-update-ssl-cert.sh -a -s /tmp/install-le.sh -a -s /tmp/validation.sh -a -s /tmp/generate-ssl-cert.sh ] && {
            mv /tmp/install-le.sh /root/install-le.sh
            mv /tmp/auto-update-ssl-cert.sh  /root/auto-update-ssl-cert.sh
            mv /tmp/generate-ssl-cert.sh /root/generate-ssl-cert.sh
            mv /tmp/validation.sh /root/validation.sh
            chmod +x /root/*.sh
            echo $latest_revision > $revision_state_path
        }
   }
}

[ -f "/var/lib/jelastic/SSL/jelastic.crt" ] && exp_date=$(jem ssl checkdomain | python -c "import sys, json; print json.load(sys.stdin)['expiredate']");
[ -z "$exp_date" ] && { echo "$(date) - no certificates for update" >> /var/log/letsencrypt.log; exit 0; };
_exp_date_unixtime=$(date --date="$exp_date" "+%s");
_cur_date_unixtime=$(date "+%s");
_delta_time=$(( $_exp_date_unixtime - $_cur_date_unixtime  ));
[[ $_delta_time -le $seconds_before_expire ]] && {
    validateLatestVersion
    echo "$(date) - update required" >> /var/log/letsencrypt.log;
    resp=$($WGET  -qO- --no-check-certificate ${auto_update_url});
    echo $resp |  grep -q 'result:0' || wget -qO- "${jerror_url}/jerror?appid=[string]&actionname=updatefromcontainer&callparameters=$auto_update_url&email=$email&errorcode=4121&errormessage=$resp&priority=high"
}
