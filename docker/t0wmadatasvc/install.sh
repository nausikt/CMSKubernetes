#!/bin/bash
#No longer using rpm for packaging t0wmadatasvc

TAG=2.1.1
WMCORE_VERSION=2.4.1
python -m pip install --upgrade pip
python -m pip install wmcore==$WMCORE_VERSION
python -m pip install --no-cache-dir git+https://github.com/dmwm/t0wmadatasvc.git@$TAG

