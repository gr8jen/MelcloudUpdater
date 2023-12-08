#!/bin/bash

## MelcloudUpdater version 1.0.0
## Inpired through albert[at]hakvoort[.]co and Giljam Val
## Expanded by Gr8jen 


## Debug mode to trace process
McDebug=On
#McDebug=Off

if [ "$McDebug" = On ] ; then echo 'DEBUG: Debug mode On';echo; fi
if [ "$McDebug" = On ] ; then echo 'DEBUG: Setting various variables';echo; fi

## Melcloud username/password
USERNAME=
PASSWORD=

## Script folder without trailing slash
FOLDER=/home/pi/melcloud_updater


## Switch between SetTankWaterTemperature when we want to increase it for the legionella run
SetTankWaterTemperatureLegionella=55
SetTankWaterTemperatureNormalMode=47
OPERATION_MODE_LEGIONELLA=6


## Send data from melcloud to a influxdb for monitoring
#SEND_TO_INFLUXDB=0
SEND_TO_INFLUXDB=1

BUCKET=
ORGANISATION=
TOKEN=
HOST=


## Path
CAT=/bin/cat
CURL=/usr/bin/curl
JQ=/usr/bin/jq
PIDOF=/bin/pidof
GREP=/bin/grep
WC=/usr/bin/wc

#Globals
mc_data=""
dom_data=""
DHeatpumpActive=""
MOperationMode=""
MHasZone2=""
MCanHeat=""
MCanCool=""
MHasHotWaterTank=""
MCurrentEnergyConsumed=""
MCurrentEnergyProduced=""


###########################################################################
#                   No changes are needed here below                      #
###########################################################################

## Start

echo "-----------------------"
echo "MelcloudUdater 1.0.0"
echo "-----------------------"


## check if we are the only local instance
if [ "$McDebug" = On ] ; then echo 'DEBUG: Checking instance';echo; fi

if [[ "`$PIDOF -x $(basename $0) -o %PPID`" ]]; then
        echo "This script is already running with PID `$PIDOF -x $(basename $0) -o %PPID`"
        exit
fi

## Check required apps availability
if [ "$McDebug" = On ] ; then echo 'DEBUG: Checking apps/paths';echo; fi

if [ ! -f $JQ ]; then
	echo "jq package is missing, check https://stedolan.github.io/jq/ or for Debian/Ubuntu -> apt-get install jq"
        exit
fi
if [ ! -f $CURL ]; then
        echo "curl is missing, or wrong path"
        exit
fi
if [ ! -f $CAT ]; then
        echo "cat is missing, or wrong path"
        exit
fi
if [ ! -f $PIDOF ]; then
        echo "pidof is missing, or wrong path"
        exit
fi
if [ ! -f $GREP ]; then
        echo "grep is missing, or wrong path"
        exit
fi
if [ ! -f $WC ]; then
        echo "wc is missing, or wrong path"
        exit
fi


# Value to keep track of an updated device to trigger MelCloud update command, always default 0, will be>
MelCloudUpdate=0

## Login on MelCloud and get Session key
if [ "$McDebug" = On ] ; then echo 'DEBUG: Testing MelCloud login and get session key';echo; fi

$CURL -s -o $FOLDER/.session 'https://app.melcloud.com/Mitsubishi.Wifi.Client/Login/ClientLogin' \
  -H 'Cookie: policyaccepted=true; gsScrollPos-189=' \
  -H 'Origin: https://app.melcloud.com' \
  -H 'Accept-Encoding: gzip, deflate, br' \
  -H 'Accept-Language: nl-NL,nl;q=0.9,en-NL;q=0.8,en;q=0.7,en-US;q=0.6,de;q=0.5' \
  -H 'Content-Type: application/json; charset=UTF-8' \
  -H 'Accept: application/json, text/javascript, */*; q=0.01' \
  -H 'Referer: https://app.melcloud.com/' -H 'X-Requested-With: XMLHttpRequest' \
  -H 'Connection: keep-alive' --data-binary '{"Email":'"\"$USERNAME\""',"Password":'"\"$PASSWORD\""',"Language":12,"AppVersion":"1.17.3.1","Persist":true,"CaptchaResponse":null}' --compressed ;


LOGINCHECK=`/bin/cat $FOLDER/.session | $JQ '.ErrorId'`

if [ "$LOGINCHECK" = "1" ]; then
        echo "----------------------------------"
        echo "|Wrong Melcloud login credentials|"
        echo "---------------------------------"
        exit
fi

SESSION=`cat $FOLDER/.session | $JQ '."LoginData"."ContextKey"' -r`

if [ "$McDebug" = On ] ; then echo 'Sessionkey: $SESSION';echo; fi

## Get Data for all Devices/Building IDs and write it to .deviceid
if [ "$McDebug" = On ] ; then echo 'DEBUG: Get data from MelCloud';echo; fi

$CURL -s -o $FOLDER/.deviceid 'https://app.melcloud.com/Mitsubishi.Wifi.Client/User/ListDevices' \
  -H 'X-MitsContextKey: '"$SESSION"'' \
  -H 'Accept-Encoding: gzip, deflate, br' \
  -H 'Accept-Language: nl-NL,nl;q=0.9,en-NL;q=0.8,en;q=0.7,en-US;q=0.6,de;q=0.5' \
  -H 'Accept: application/json, text/javascript, */*; q=0.01' \
  -H 'Referer: https://app.melcloud.com/' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H 'Cookie: policyaccepted=true; gsScrollPos-189=' \
  -H 'Connection: keep-alive' --compressed


## Check if there are multiple units, this script is (currently) only for 1 unit.
if [ "$McDebug" = On ] ; then echo 'DEBUG: Check number of devices :only one device is currently supported';echo; fi

CHECKUNITS=`cat $FOLDER/.deviceid | $JQ '.' -r | $GREP DeviceID | $WC -l`

if [ $CHECKUNITS -gt 2 ]; then
        echo "Multiple units found, this script cannot yet handle more then 1 unit.."
        exit
fi

DEVICEID=`cat $FOLDER/.deviceid | $JQ '.' -r | grep DeviceID | head -n1 | cut -d : -f2 | xargs | sed 's/.$//'`
BUILDINGID=`cat $FOLDER/.deviceid | $JQ '.' -r | grep BuildingID | head -n1 | cut -d : -f2 | xargs | sed 's/.$//'`

echo DeviceID=$DEVICEID
echo BuildingID=$BUILDINGID

## Read and prepare data set (remove [] characters) and write it to .meldata
if [ "$McDebug" = On ] ; then echo 'DEBUG: Preparing dataset';echo; fi

fulldata=$( cat $FOLDER/.deviceid )
echo "${fulldata:1:${#fulldata}-2}" > $FOLDER/.meldata>&1

## Check if data output is fine
/bin/cat $FOLDER/.meldata | $JQ -e . >/dev/null 2>&1

if [ ${PIPESTATUS[1]} != 0 ]; then
        echo "Retrieved Data is not json compatible, something went wrong....Help...."
        exit
fi

if [ "$McDebug" = On ] ; then echo 'DEBUG: Data is fine, you can check it in file .meldata';echo; fi


LastCommunication=`date +%Y-%m-%dT%T.%3N`
NextCommunication=`date -d "today 1 minutes" +%Y-%m-%dT%T.%3N`


OPERATIONMODE=`cat $FOLDER/.deviceid | $JQ '.' -r | grep -w OperationMode | head -n1 | cut -d : -f2 | xargs | sed 's/.$//'`
CurrentTankWaterTemperature=`cat $FOLDER/.deviceid | $JQ '.[].Structure.Devices[].Device' -r | grep -w "TankWaterTemperature" | head -n1 | cut -d : -f2 | xargs | sed 's/.$//'`
CurrentSetTankWaterTemperature=`cat $FOLDER/.deviceid | $JQ '.[].Structure.Devices[].Device' -r | grep -w "SetTankWaterTemperature" | head -n1 | cut -d : -f2 | xargs | sed 's/.$//'`
CurrentTankWaterTemperature=${CurrentTankWaterTemperature%.*}

## When the OperationMode has the Legionella mode,then we need to increase the SetTankWaterTemperature, this will make sure that water is  heated by the compressor
if [ $OPERATIONMODE -eq $OPERATION_MODE_LEGIONELLA ] && [ $CurrentTankWaterTemperature -lt $SetTankWaterTemperatureLegionella ]; then

	if [ "$McDebug" = On ] ; then
		echo "Increase SetTankWaterTemperature"
  		echo OPERATIONMODE=$OPERATIONMODE
       		echo CurrentTankWaterTemperature=$CurrentTankWaterTemperature
        	echo CurrentSetTankWaterTemperature=$CurrentSetTankWaterTemperature
	fi

	MelCloudUpdate=1
  	mcString=$(</home/pi/melcloud_updater/.meldata jq -r '.Structure.Devices[] | {"EffectiveFlags":281475043819552,SetTankWaterTemperature:'$SetTankWaterTemperatureLegionella',HCControlType:1,DeviceID:.Device.DeviceID,DeviceType:.Device.DeviceType,Scene:.Device.Scene,SceneOwner:.Device.SceneOwner,UnitStatus:.Device.UnitStatus,Zone1Name:.Zone1Name,Zone2Name:.Zone2Name,OperationMode:.Device.OperationMode,OperationModeZone1:.Device.OperationModeZone1,OperationModeZone2:.Device.OperationModeZone2,SetTemperatureZone1:.Device.SetTemperatureZone1,SetTemperatureZone2:.Device.SetTemperatureZone2,SetCoolFlowTemperatureZone1:.Device.SetCoolFlowTemperatureZone1,SetCoolFlowTemperatureZone2:.Device.SetCoolFlowTemperatureZone2,SetHeatFlowTemperatureZone1:.Device.SetHeatFlowTemperatureZone1,SetHeatFlowTemperatureZone2:.Device.SetHeatFlowTemperatureZone2,EcoHotWater:.Device.EcoHotWater,ForcedHotWaterMode:.Device.ForcedHotWaterMode,HasPendingCommand:false,HolidayMode:.Device.HolidayMode,IdleZone1:.Device.IdleZone1,IdleZone2:.Device.IdleZone2,Offline:.Device.Offline,DemandPercentage:.Device.DemandPercentage,Power:.Device.Power,ProhibitHotWater:.Device.ProhibitHotWater,ProhibitZone1:.Device.ProhibitZone1,ProhibitZone2:.Device.ProhibitZone2,TemperatureIncrementOverride:.Device.TemperatureIncrementOverride,"LastCommunication":'"\"$LastCommunication\""',"NextCommunication":'"\"$NextCommunication\""',"ErrorCode":.Device.ErrorCode,"ErrorMessage":.Device.ErrorMessage,"ForcedHotWaterMode":.Device.ForcedHotWaterMode,"LocalIPAddress":.Device.LocalIPAddress,"OutdoorTemperature":.Device.OutdoorTemperature,"RoomTemperatureZone1":.Device.RoomTemperatureZone1,"RoomTemperatureZone2":.Device.RoomTemperatureZone2,"TankWaterTemperature":.Device.TankWaterTemperature}' | tr -d '[:space:]')
fi


## When the OperationMode is running in Legionella mode and we reach the target 'TankWaterTemperature', we can set the 'SetTankWaterTemperature' back to its normal value
if [ $OPERATIONMODE -eq $OPERATION_MODE_LEGIONELLA ] && [ $CurrentSetTankWaterTemperature -eq $SetTankWaterTemperatureLegionella ] && [ $CurrentTankWaterTemperature -ge $SetTankWaterTemperatureLegionella ]; then

        if [ "$McDebug" = On ] ; then
		echo "Decrease SetTankWaterTemperature"
        	echo OPERATIONMODE=$OPERATIONMODE
                echo CurrentTankWaterTemperature=$CurrentTankWaterTemperature
                echo CurrentSetTankWaterTemperature=$CurrentSetTankWaterTemperature
	fi

        mcString=$(</home/pi/melcloud_updater/.meldata jq -r '.Structure.Devices[] | {"EffectiveFlags":281475043819552,SetTankWaterTemperature:'$SetTankWaterTemperatureNormalMode',HCControlType:1,DeviceID:.Device.DeviceID,DeviceType:.Device.DeviceType,Scene:.Device.Scene,SceneOwner:.Device.SceneOwner,UnitStatus:.Device.UnitStatus,Zone1Name:.Zone1Name,Zone2Name:.Zone2Name,OperationMode:.Device.OperationMode,OperationModeZone1:.Device.OperationModeZone1,OperationModeZone2:.Device.OperationModeZone2,SetTemperatureZone1:.Device.SetTemperatureZone1,SetTemperatureZone2:.Device.SetTemperatureZone2,SetCoolFlowTemperatureZone1:.Device.SetCoolFlowTemperatureZone1,SetCoolFlowTemperatureZone2:.Device.SetCoolFlowTemperatureZone2,SetHeatFlowTemperatureZone1:.Device.SetHeatFlowTemperatureZone1,SetHeatFlowTemperatureZone2:.Device.SetHeatFlowTemperatureZone2,EcoHotWater:.Device.EcoHotWater,ForcedHotWaterMode:.Device.ForcedHotWaterMode,HasPendingCommand:false,HolidayMode:.Device.HolidayMode,IdleZone1:.Device.IdleZone1,IdleZone2:.Device.IdleZone2,Offline:.Device.Offline,DemandPercentage:.Device.DemandPercentage,Power:.Device.Power,ProhibitHotWater:.Device.ProhibitHotWater,ProhibitZone1:.Device.ProhibitZone1,ProhibitZone2:.Device.ProhibitZone2,TemperatureIncrementOverride:.Device.TemperatureIncrementOverride,"LastCommunication":'"\"$LastCommunication\""',"NextCommunication":'"\"$NextCommunication\""',"ErrorCode":.Device.ErrorCode,"ErrorMessage":.Device.ErrorMessage,"ForcedHotWaterMode":.Device.ForcedHotWaterMode,"LocalIPAddress":.Device.LocalIPAddress,"OutdoorTemperature":.Device.OutdoorTemperature,"RoomTemperatureZone1":.Device.RoomTemperatureZone1,"RoomTemperatureZone2":.Device.RoomTemperatureZone2,"TankWaterTemperature":.Device.TankWaterTemperature}' | tr -d '[:space:]')
        MelCloudUpdate=1
fi


if [ $MelCloudUpdate -eq 1 ]; then

	if [ "$McDebug" = On ] ; then
		echo "updating melcoud"
		echo mcString=''"$mcString"''
	fi

	curl  -s -o $FOLDER/.deviceid 'https://app.melcloud.com/Mitsubishi.Wifi.Client/Device/SetAtw' \
	  -H 'authority: app.melcloud.com' \
	  -H 'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="99", "Google Chrome";v="99"' \
	  -H 'x-mitscontextkey: '"$SESSION"'' \
	  -H 'sec-ch-ua-mobile: ?0' \
	  -H 'user-agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.74 Safari/537.36' \
	  -H 'content-type: application/json; charset=UTF-8' \
	  -H 'accept: application/json, text/javascript, */*; q=0.01' \
	  -H 'x-requested-with: XMLHttpRequest' \
	  -H 'sec-ch-ua-platform: "Linux"' \
	  -H 'origin: https://app.melcloud.com' \
	  -H 'sec-fetch-site: same-origin' \
	  -H 'sec-fetch-mode: cors' \
	  -H 'sec-fetch-dest: empty' \
	  -H 'referer: https://app.melcloud.com/' \
	  -H 'accept-language: nl-NL,nl;q=0.9,en-US;q=0.8,en;q=0.7' \
	  --data-raw ''"$mcString"'' \
	  --compressed

fi

## Get the data and upload to Influxdb
if [ $SEND_TO_INFLUXDB -eq 1 ]; then

	INFLUXDB_DATA=$(</home/pi/melcloud_updater/.meldata jq -r '.Structure.Devices[].Device | { HeatPumpFrequency : .HeatPumpFrequency, MaxSetTemperature : .MaxSetTemperature, MinSetTemperature : .MinSetTemperature, RoomTemperatureZone1 : .RoomTemperatureZone1, OutdoorTemperature : .OutdoorTemperature, FlowTemperature : .FlowTemperature, FlowTemperatureZone1 : .FlowTemperatureZone1, FlowTemperatureBoiler : .FlowTemperatureBoiler, ReturnTemperature : .ReturnTemperature, ReturnTemperatureZone1 : .ReturnTemperatureZone1, ReturnTemperatureBoiler : .ReturnTemperatureBoiler, TankWaterTemperature : .TankWaterTemperature, MixingTankWaterTemperature : .MixingTankWaterTemperature, DailyHeatingEnergyConsumed : .DailyHeatingEnergyConsumed, DailyCoolingEnergyConsumed : .DailyCoolingEnergyConsumed, DailyHotWaterEnergyConsumed : .DailyHotWaterEnergyConsumed, DailyHeatingEnergyProduced : .DailyHeatingEnergyProduced, DailyCoolingEnergyProduced : .DailyCoolingEnergyProduced, DailyHotWaterEnergyProduced : .DailyHotWaterEnergyProduced, SetTankWaterTemperature : .SetTankWaterTemperature, TargetHCTemperatureZone1 : .TargetHCTemperatureZone1, SetHeatFlowTemperatureZone1 : .SetHeatFlowTemperatureZone1, SetCoolFlowTemperatureZone1 : .SetCoolFlowTemperatureZone1, MaxTankTemperature : .MaxTankTemperature, HeatPumpFrequency : .HeatPumpFrequency, OperationModeZone1 : .OperationModeZone1, OperationMode : .OperationMode, MixingTankWaterTemperature : .MixingTankWaterTemperature, CondensingTemperature : .CondensingTemperature, DefrostMode : .DefrostMode , CurrentEnergyConsumed : .CurrentEnergyConsumed, CurrentEnergyProduced : .CurrentEnergyProduced}' | sed 's/:/\=/' | tr '\n{}"' ' ' | tr -d '[:space:]' )

        if [ "$McDebug" = On ] ; then
		echo "temperatures $INFLUXDB_DATA"
	fi

	curl --request POST ''"$HOST"'/api/v2/write?org='"$ORGANISATION"'&bucket='"$BUCKET"'&precision=s' \
	  --header 'Authorization: Token '"$TOKEN"'' \
	  --header 'Content-Type: text/plain; charset=utf-8' \
	  --header 'Accept: application/json' \
	  --data-binary "temperatures $INFLUXDB_DATA"
fi
