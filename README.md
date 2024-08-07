# MelcloudUpdater 1.1.0

Tool for extracting data from Melcloud Ecodan and update Setpoint (only 1x Air/Water unit!! Air/Air isn't working)

Installation guide based on Debian based systems

## 1) Requirements :

curl and jq (https://stedolan.github.io/jq/)

```
sudo apt-get install curl jq
``````

## 2) Create folder and download script

```
mkdir -p /home/pi/melcloud_updater

cd /home/pi/melcloud_updater

wget https://raw.githubusercontent.com/gr8jen/MelcloudUpdater/master/melcloud_updater.sh

chmod +x melcloud_updater.sh
```

## 3) Install InfluxDB to make dashboards from Melcloud data.

- Go to (https://docs.influxdata.com/influxdb/v2/install) and choose your OS like Linux or Raspberry
- Run in docker via ```docker pull influxdb:2.7.3```

Configure as shown at: https://docs.influxdata.com/influxdb/v2/install/#set-up-influxdb-through-the-ui
## 4) Edit melcloud_updater.sh and fill in : 

-> username&password for Melcloud

-> path of the used programs

-> Setpoint for normal operation and Legionella (if you want something else)

-> Time each day you want to run SWW (if you want something else)

-> for Influxdb:

        BUCKET
        ORGANISATION
        TOKEN
        HOST


## 5) Start the script and check the output of it. Then check if the data is in Influxdb

```
/home/pi/melcloud_updater/melcloud_updater.sh
``` 

## 6) If everything works fine add a job to the crontab

```
crontab -e
```

  */3 * * * *   /home/pi/melcloud_updater/melcloud_updater.sh
  
  (since the ~ october 2023 firmware update the time must be changed from 2 to 3 minutes)
  
