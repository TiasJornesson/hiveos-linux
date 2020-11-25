#!/usr/bin/env bash

# 16.09.20 set min soc clock level via ppt based on memclock

VEGA20=$( lspci -vnns $busid | grep VGA -A 2 | grep AMD -A 2 | grep Vega -A 2 | grep "Vega 20" | wc -l )
#NAVI=$( lspci -vnns $busid | grep Navi | wc -l )

NAVI_VDDCI_MIN=650
NAVI_VDDCI_MAX=850
NAVI_MVDD_MIN=1200
NAVI_MVDD_MAX=1350

echo "manual" > /sys/class/drm/card$cardno/device/power_dpm_force_performance_level

if [[ $NAVI_COUNT -ne 0 ]]; then
    args=""
    if [[ ! -z $VDDCI && ${VDDCI[$i]} -ge $NAVI_VDDCI_MIN && ${VDDCI[$i]} -le $NAVI_VDDCI_MAX ]]; then
       vlt_vddci=$((${VDDCI[$i]} * 4 ))
       args+="smcPPTable/MemVddciVoltage/1=${vlt_vddci} smcPPTable/MemVddciVoltage/2=${vlt_vddci} smcPPTable/MemVddciVoltage/3=${vlt_vddci} "
    fi
    if [[ ! -z $MVDD && ${MVDD[$i]} -ge $NAVI_MVDD_MIN && ${MVDD[$i]} -le $NAVI_MVDD_MAX ]]; then
       vlt_mvdd=$((${MVDD[$i]} * 4 ))
       args+="smcPPTable/MemMvddVoltage/1=${vlt_mvdd} smcPPTable/MemMvddVoltage/2=${vlt_mvdd} smcPPTable/MemMvddVoltage/3=${vlt_mvdd} "
    fi
    python /hive/opt/upp/upp.py -i /sys/class/drm/card$cardno/device/pp_table set \
    	smcPPTable/FanStopTemp=0 smcPPTable/FanStartTemp=0 smcPPTable/FanZeroRpmEnable=0 \
    	smcPPTable/MinVoltageGfx=2800 $args \
    	OverDrive8Table/ODSettingsMax/8=960 \
    	OverDrive8Table/ODSettingsMin/3=700 OverDrive8Table/ODSettingsMin/5=700 OverDrive8Table/ODSettingsMin/7=700 \
    	--write
fi
#	smcPPTable/FanTargetTemperature=85
#	smcPPTable/MemMvddVoltage/3=5200
#	smcPPTable/MemVddciVoltage/3=3200
#	smcPPTable/FanPwmMin=35
#	OverDrive8Table/ODFeatureCapabilities/9=0

function _SetcoreVDDC {
	if [[ $VEGA20 -ne 0 || $NAVI_COUNT -ne 0  ]]; then
		echo "Noop"
	else
		vegatool -i $cardno --volt-state 7 --vddc-table-set $1 --vddc-mem-table-set $1
	fi
}

function _SetcoreClock {
	local vdd=$2
	if [[ $VEGA20 -ne 0 || $NAVI_COUNT -ne 0 ]]; then
		echo "s 1 $1" > /sys/class/drm/card$cardno/device/pp_od_clk_voltage
		[[  -z $vdd  ]] && vdd="1050"
		[[  -z $vdd  && $NAVI_COUNT -ne 0 ]] && vdd="0"
		[[ $vdd -gt 725 ]] && echo "vc 1 $(($1-100)) $(($vdd-25))" > /sys/class/drm/card$cardno/device/pp_od_clk_voltage
		echo "vc 2 $1 $vdd" > /sys/class/drm/card$cardno/device/pp_od_clk_voltage
		echo c > /sys/class/drm/card$cardno/device/pp_od_clk_voltage

	else
		vegatool -i $cardno  --core-state 1 --core-clock $1
	        vegatool -i $cardno  --core-state 2 --core-clock $(($1+10))
        	vegatool -i $cardno  --core-state 3 --core-clock $(($1+20))
	        vegatool -i $cardno  --core-state 4 --core-clock $(($1+30))
	        vegatool -i $cardno  --core-state 5 --core-clock $(($1+40))
	        vegatool -i $cardno  --core-state 6 --core-clock $(($1+50))
	        vegatool -i $cardno  --core-state 7 --core-clock $(($1+60))
	fi
}

function _SetmemClock {
	if [[ $VEGA20 -ne 0 || $NAVI_COUNT -ne 0 ]]; then
		echo "m 1 $1" > /sys/class/drm/card$cardno/device/pp_od_clk_voltage
		echo c > /sys/class/drm/card$cardno/device/pp_od_clk_voltage
	else
	        #vegatool -i $cardno --mem-state 3 --mem-clock $1

		# ema
		# if mem clock < 848  set SocClock to 847 for state 3
		# if mem clock < 961  set SocClock to 960 for state 3
		# if mem clock < 1029 set SocClock to 1028 for state 3
		# 84700
		echo "---" >> /tmp/ema.txt
		TESTSOC=$(sudo python /hive/opt/upp/upp.py -i /sys/class/drm/card$cardno/device/pp_table get SocClockDependencyTable/Entries/3/ulClk 2> /dev/null)
		if [ "$1" -lt 848 ]; then
			#echo "less than 848"
			if [ $TESTSOC -ne "84700" ]; then
				echo "Card $cardno MemClock $1 apply 847 SocClock" >> /tmp/ema.txt
				python /hive/opt/upp/upp.py -i /sys/class/drm/card$cardno/device/pp_table set \
				/SocClockDependencyTable/3/ulClk=84700 \
				--write
			else
				echo "Card $cardno MemClock $1 SocClock $TESTSOC" >> /tmp/ema.txt
            	fi
		elif [ "$1" -lt 961 ]; then
			#echo "less than 961"
			if [ $TESTSOC -ne "96000" ]; then
				echo "Card $cardno MemClock $1 apply 960 SocClock" >> /tmp/ema.txt
				python /hive/opt/upp/upp.py -i /sys/class/drm/card$cardno/device/pp_table set \
				/SocClockDependencyTable/3/ulClk=96000 \
				--write
			else
				echo "Card $cardno MemClock $1 SocClock $TESTSOC" >> /tmp/ema.txt
            	fi
		elif [ "$1" -lt 1029 ]; then
			#echo "less than 1029"
			if [ $TESTSOC -ne "102800" ]; then
				echo "Card $cardno MemClock $1 apply 1028 SocClock" >> /tmp/ema.txt
				python /hive/opt/upp/upp.py -i /sys/class/drm/card$cardno/device/pp_table set \
				/SocClockDependencyTable/3/ulClk=102800 \
				--write
			else
				echo "Card $cardno MemClock $1 SocClock $TESTSOC" >> /tmp/ema.txt
            	fi
		elif [ "$1" -lt 1108 ]; then
                        #echo "less than 1108"
                        if [ $TESTSOC -ne "110700" ]; then
                                echo "Card $cardno MemClock $1 apply 1107 SocClock" >> /tmp/ema.txt
                                python /hive/opt/upp/upp.py -i /sys/class/drm/card$cardno/device/pp_table set \
                                /SocClockDependencyTable/3/ulClk=110700 \
                                --write
                        else
                                echo "Card $cardno MemClock $1 SocClock $TESTSOC" >> /tmp/ema.txt
                fi
        	else
		        echo "??? Card $cardno MemClock $1 SocClock $TESTSOC" >> /tmp/ema.txt
		fi

	        vegatool -i $cardno --mem-state 3 --mem-clock $1
        	#ema
	        #setta mem p3
	        rocm-smi -d $cardno --setmclk 3
	        #setta core p1
	        rocm-smi -d $cardno --setsclk 1
		#ema
	fi
}


#if [[ ! -z $MEM_CLOCK && ${MEM_CLOCK[$i]} -gt 0 ]]; then
#	_SetmemClock ${MEM_CLOCK[$i]}
#fi

if [[ ! -z $CORE_CLOCK && ${CORE_CLOCK[$i]} -gt 0 ]]; then
	_SetcoreClock ${CORE_CLOCK[$i]} ${CORE_VDDC[$i]}
fi

if [[ ! -z $CORE_VDDC && ${CORE_VDDC[$i]} -gt 0 ]]; then
	_SetcoreVDDC ${CORE_VDDC[$i]}
fi

if [[ ! -z $MEM_CLOCK && ${MEM_CLOCK[$i]} -gt 0 ]]; then
        _SetmemClock ${MEM_CLOCK[$i]}
fi

[[ ! -z $REF && ${REF[$i]} -gt 0 ]] && amdmemtweak --gpu $card_idx --REF ${REF[$i]}

	echo 1 > /sys/class/drm/card$cardno/device/hwmon/hwmon*/pwm1_enable
	echo "manual" > /sys/class/drm/card$cardno/device/power_dpm_force_performance_level
	echo 5 > /sys/class/drm/card$cardno/device/pp_power_profile_mode
	#vegatool -i $cardno --set-fanspeed 50
	if [[ $VEGA20 -ne 0 || $NAVI_COUNT -ne 0 ]]; then
		rocm-smi -d $cardno --setfan 50%
	else
		vegatool -i $cardno  --set-fanspeed 50
	fi


[[ ! -z $FAN && ${FAN[$i]} -gt 0 ]] &&
	if [[ $VEGA20 -ne 0 || $NAVI_COUNT -ne 0 ]]; then
		rocm-smi -d $cardno --setfan ${FAN[$i]}%
	else
		vegatool -i $cardno  --set-fanspeed ${FAN[$i]}
	fi


if [[ ! -z $PL && ${PL[$i]} -gt 0 ]]; then
	hwmondir=`realpath /sys/class/drm/card$cardno/device/hwmon/hwmon*/`
	if [[ -e ${hwmondir}/power1_cap_max ]] && [[ -e ${hwmondir}/power1_cap ]]; then
#		echo Power Limit set to ${PL[$i]} W
		rocm-smi -d $cardno --autorespond=y --setpoweroverdrive ${PL[$i]} # --loglevel error
	fi
fi
