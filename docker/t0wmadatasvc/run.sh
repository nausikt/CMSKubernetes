#!/bin/bash
# script to start t0wmadatasvc

srv=`echo $USER | sed -e "s,_,,g"`
STATEDIR=/data/srv/state/$srv
LOGDIR=/data/srv/logs/$srv
AUTHDIR=/data/srv/current/auth/$srv
CONFIGDIR=/data/srv/current/config/$srv
CONFIGFILE=${CONFIGFILE:-config.py}
CFGFILE=/etc/secrets/$CONFIGFILE

### Ensure the right ownership.
sudo chown -R $USER.$USER /data

### Populate WMCore conventional directory areas.
mkdir -p $LOGDIR
mkdir -p $STATEDIR
mkdir -p $AUTHDIR
mkdir -p $CONFIGDIR
mkdir -p $AUTHDIR/../wmcore-auth

# overwrite host PEM files in /data/srv area by the robot certificate
# Note that the proxy file is not required and used
if [ -f /etc/robots/robotkey.pem ]; then
    sudo cp /etc/robots/robotkey.pem $AUTHDIR/dmwm-service-key.pem
    sudo cp /etc/robots/robotcert.pem $AUTHDIR/dmwm-service-cert.pem
    sudo chown $USER.$USER $AUTHDIR/dmwm-service-key.pem
    sudo chown $USER.$USER $AUTHDIR/dmwm-service-cert.pem
    sudo chmod 0400 $AUTHDIR/dmwm-service-key.pem
fi

if [ -e $AUTHDIR/dmwm-service-cert.pem ] && [ -e $AUTHDIR/dmwm-service-key.pem ]; then
    export X509_USER_CERT=$AUTHDIR/dmwm-service-cert.pem
    export X509_USER_KEY=$AUTHDIR/dmwm-service-key.pem
fi

# overwrite proxy if it is present in /etc/proxy
if [ -f /etc/proxy/proxy ]; then
    export X509_USER_PROXY=/etc/proxy/proxy
    mkdir -p $STATEDIR/proxy
    if [ -f $STATEDIR/proxy/proxy.cert ]; then
        rm $STATEDIR/proxy/proxy.cert
    fi
    ln -s /etc/proxy/proxy $STATEDIR/proxy/proxy.cert
    mkdir -p $AUTHDIR/../proxy
    if [ -f $AUTHDIR/../proxy/proxy ]; then
        rm $AUTHDIR/../proxy/proxy
    fi
    ln -s /etc/proxy/proxy $AUTHDIR/../proxy/proxy
fi

# overwrite header-auth key file with one from secrets

if [ -f /etc/hmac/hmac ]; then
    mkdir -p /data/srv/current/auth/wmcore-auth
    if [ -f /data/srv/current/auth/wmcore-auth/header-auth-key ]; then
        sudo rm /data/srv/current/auth/wmcore-auth/header-auth-key
    fi
    sudo cp /etc/hmac/hmac /data/srv/current/auth/wmcore-auth/header-auth-key
    sudo chown $USER.$USER /data/srv/current/auth/wmcore-auth/header-auth-key
    mkdir -p /data/srv/current/auth/$srv
    if [ -f /data/srv/current/auth/$srv/header-auth-key ]; then
        sudo rm /data/srv/current/auth/$srv/header-auth-key
    fi
    sudo cp /etc/hmac/hmac /data/srv/current/auth/$srv/header-auth-key
    sudo chown $USER.$USER /data/srv/current/auth/$srv/header-auth-key
fi

# overwrite header-auth key file with one from secrets
if [ -f /etc/hmac/hmac ]; then
    if [ -f $AUTHDIR/../wmcore-auth/header-auth-key ]; then
        sudo rm $AUTHDIR/../wmcore-auth/header-auth-key
    fi
    if [ -f $AUTHDIR/header-auth-key ]; then
        sudo rm $AUTHDIR/header-auth-key
    fi
    sudo cp /etc/hmac/hmac $AUTHDIR/../wmcore-auth/header-auth-key
    sudo chown $USER.$USER $AUTHDIR/../wmcore-auth/header-auth-key
    sudo chmod 0600 $AUTHDIR/../wmcore-auth/header-auth-key

    sudo cp /etc/hmac/hmac $AUTHDIR/header-auth-key
    sudo chown $USER.$USER $AUTHDIR/header-auth-key
    sudo chmod 0600 $AUTHDIR/header-auth-key
fi

# use service configuration files from /etc/secrets if they are present
files=`ls /etc/secrets`
for fname in $files; do
    if [ -f /etc/secrets/$fname ]; then
        if [ -f $CONFIGDIR/$fname ]; then
            rm $CONFIGDIR/$fname
        fi
        sudo cp /etc/secrets/$fname $CONFIGDIR/$fname
        sudo chown $USER.$USER $CONFIGDIR/$fname
    fi
done
files=`ls /etc/secrets`
for fname in $files; do
    if [ ! -f $CONFIGDIR/$fname ]; then
        sudo cp /etc/secrets/$fname $AUTHDIR/$fname
        sudo chown $USER.$USER $AUTHDIR/$fname
    fi
done

cp /data/manage $CONFIGDIR/manage
# start the service
$CONFIGDIR/manage start 'I did read documentation'

# run monitoring script
if [ -f /data/monitor.sh ]; then
    /data/monitor.sh
fi
