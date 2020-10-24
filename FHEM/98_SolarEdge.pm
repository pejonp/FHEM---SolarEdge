##############################################
# $Id: 98_SolarEdge.pm 0037 2020-24-10 17:54:00Z pejonp $
#
#	fhem Modul für Wechselrichter SolarEdge SE5K
#	verwendet Modbus.pm als Basismodul für die eigentliche Implementation des Protokolls.
#
#	This file is part of fhem.
#
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
##############################################################################
#	Changelog:
#	2015-04-16	Vorlage 98_ModbusSDM220M.pm / 98_Pluggit.pm
# 2018-10-15  weiter ... pejonp
# 2018-10-29  X_PV_Energy X_PV_EnergyToday X_PV_EnergyCurrentWeek pv_energytomont ...
# 2020-03-08  Anpassungen von CaptainRoot (https://github.com/CaptainRoot/FHEM---SolarEdge) FHEM-Forum (https://forum.fhem.de/index.php/topic,80767.msg947778.html#msg947778) übernommen
# 2020-04-20  PBP  :pejonp
# 2020-05-03  Undefined subroutine &SolarEdge::ExprMppt (PBP) :pejonp 
# 2020-11-10  Anpassung X-Meter
# 2020-13-10  Auslesen X_Meter_C_Model usw.  Fehlerbehebung
# 2020-15-10  kleine Anpassungen
# 2020-21-10  ModBus-Register für Batterie eingetragen
# 2020-22-10  Bat Register hinzugefügt
# 2020-22-10  Apparent Power, Reactive Power, Power Factor, Reg Apparent Energy wieder mit aufgenommen
# 2020-24-10  unpack angepasst



use strict;
use warnings;

sub ExprMppt {
    my ( $hash, $DevName, $ReadingName, $vval_0 , $vval_1 , $vval_2 , $vval_3 , $vval_4 ) = @_;
    return SolarEdge_ExprMppt( $hash, $DevName, $ReadingName, $vval_0 , $vval_1 , $vval_2 , $vval_3 , $vval_4 );
}

sub ExprMeter {
    my ( $hash, $DevName, $ReadingName, $vval_0 , $vval_1 , $vval_2 , $vval_3 , $vval_4 , $vval_5 , $vval_6 , $vval_7 , $vval_8 ) = @_;
    return SolarEdge_ExprMeter( $hash, $DevName, $ReadingName, $vval_0 , $vval_1 , $vval_2 , $vval_3 , $vval_4, $vval_5 , $vval_6 , $vval_7 , $vval_8 );
}

package FHEM::SolarEdge;


no if $] >= 5.017011, warnings => 'experimental::smartmatch';
#no warnings 'portable';    # Support for 64-bit ints required
use Time::Local;
use Time::HiRes qw(gettimeofday usleep);
use Device::SerialPort;
use GPUtils qw(GP_Import GP_Export);
use Scalar::Util qw(looks_like_number);
use feature qw/say switch/;
use SetExtensions;
use Math::Round qw/nearest/;

use FHEM::Meta;
main::LoadModule( 'Modbus');
main::LoadModule( 'ModbusAttr');



## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(
          readingsBulkUpdate
          readingsBeginUpdate
          readingsEndUpdate
          defs
          modules
          Log3
          attr
          readingFnAttributes
          AttrVal
          ReadingsVal
          Value
          FmtDateTime
          strftime
          GetTimeSpec
          InternalTimer
          AssignIoPort
          DevIo_CloseDev
          DevIo_OpenDev
          DevIo_SimpleWrite
          DevIo_SimpleRead
          RemoveInternalTimer
          getUniqueId
          getKeyValue
          TimeNow
          Dispatch
          Initialize
          ModbusLD_Initialize
          InitializeLD
          ReadingsTimestamp
           )
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      ExprMppt
      ExprMeter
      )
);


my $SolarEdge_Version = '0023 - 08.03.2020';

my %SolarEdgedeviceInfo = (
    "h" => {
        'combine' => '40',
        'defPoll' => '1',
    },
    "type-VT_String" => {
        'decode'  => 'cp850',
        'encode'  => 'utf8',
        'expr'    => '$val =~ s/[\00]+//gr',
        'len'     => '8',
        'revRegs' => '0',
        'unpack'  => 'a16',
        'poll'    => 'once',                   # only poll once after define (or after a set)
    },
    "type-VT_String4" => {
        'decode'  => 'cp850',
        'encode'  => 'utf8',
        'expr'    => '$val =~ s/[\00]+//gr',
        'len'     => '5',
        'revRegs' => '0',
        'unpack'  => 'a8',
    },
    
);

my %SolarEdgeparseInfo = (
###############################################################################################################
    # Holding Register
###############################################################################################################
    "h40000" => {    # 40001 2 C_SunSpec_ID uint32 Wert = "SunS" (0x53756e53). Identifiziert dies eindeutig als eine SunSpec Modbus-Karte
        'len'     => '2',
        'reading' => 'C_SunSpec_ID',
        'revRegs' => '0',
        'unpack'  => 'a4',
        'poll'    => 'once',
    },
    "h40004" => {    # 40005 16 C_Hersteller String(32) Bei SunSpec eingetragener Wert = " SolarEdge "
        'reading' => 'C_Manufacturer',
        'type'    => 'VT_String',
    },
    "h40020" => {
        'reading' => 'Block_C_Model',
        'type'    => 'VT_String',
        'expr'    => 'ExprMppt($hash,$name,"C_Model",$val[0],0,0,0,0)',     # Model wird gesetzt
    },
    "h40044" => {
        'reading' => 'C_Version',
        'type'    => 'VT_String',
    },
    "h40052" => {
        'reading' => 'C_SerialNumber',
        'type'    => 'VT_String',
    },
    "h40068" => {                                                          # MODBUS Unit ID
        'reading' => 'C_DeviceAddress',
        'defPoll' => '0',
        'poll'    => 'once',
    },
    "h40069" => {    # 40070 1 C_SunSpec_DID uint16 101 = Einphasig 102 = Spaltphase1 103 = Dreiphasig
        'reading' => 'C_SunSpec_DID',                                        # name of the reading for this value
        'len'     => '1',
        'map'     => '101:single phase, 102:split phase, 103:three phase',
        'poll'    => 'once',
    },

    #  "h40071"	=>	{	# 40072 1 I_AC_Strom uint16 Ampere AC-Gesamtstromwert
    #				'reading'		=> 'I_AC_Current',			# name of the reading for this value
    #         'format'		=> '%.2f A',
    #        },
    #  "h40072"	=>	{	# 40073 1 I_AC_StromA uint16 Ampere AC-Phase A (L1) Stromwert
    #				'reading'		=> 'I_AC_CurrentL1',			# name of the reading for this value
    #        'format'		=> '%.2f A',
    #        },
    #  "h40073"	=>	{	# 40074 1 I_AC_StromB uint16 Ampere AC-Phase B (L2) Stromwert
    #				'reading'		=> 'I_AC_CurrentL2',			# name of the reading for this value
    #        'format'		=> '%.2f A',
    #        },
    #  "h40074"	=>	{	# 40075 1 I_AC_StromC uint16 Ampere AC-Phase C (L3) Stromwert
    #				'reading'		=> 'I_AC_CurrentL3',			# name of the reading for this value
    #        'format'		=> '%.2f A',
    #        },
    #  "h40075"	=>	{	# 40076 1 I_AC_Strom_SF uint16 AC-Strom Skalierungsfaktor
    #				'reading'		=> 'I_AC_Current_SF',			# name of the reading for this value
    #        },

    "h40071" => {    # 40072 (Len 5) 40072 to 40076
        'len'     => '5',                  #I_AC_Current, I_AC_CurrentA, I_AC_CurrentB, I_AC_CurrentC, I_AC_Current_SF
        'reading' => 'Block_AC_Current',
        'unpack'  => 'nnnns>',
        'expr' => 'ExprMppt($hash,$name,"I_AC_Current",$val[0],$val[1],$val[2],$val[3],$val[4])',    # conversion of raw value to visible value
    },
    "h40076" => {                                                                                    #AC Voltage Phase AB value
        'reading' => 'I_AC_VoltageAB',
    },
    "h40077" => {                                                                                    #AC Voltage Phase BC value
        'reading' => 'I_AC_VoltageBC',
    },
    "h40078" => {                                                                                    #AC Voltage Phase CA value
        'reading' => 'I_AC_VoltageCA',
    },
    "h40079" => {                                                                                    #AC Voltage Phase AN value
        'reading' => 'I_AC_VoltageAN',
    },
    "h40080" => {                                                                                    #AC Voltage Phase BN value
        'reading' => 'I_AC_VoltageBN',
    },
    "h40081" => {                                                                                    #AC Voltage Phase CN value
        'reading' => 'I_AC_VoltageCN',
    },
    "h40082" => {                                                                                    #
        'reading' => 'I_AC_Voltage_SF',
       # 'unpack'  => 's>',
    },

    #  "h40083"	=>	{	# 40084 1 I_AC_Leistung int16 Watt AC-Leistungswert
    #				'reading'	=> 'I_AC_Power',
    #        },
    #  "h40084"	=>	{	#
    #				'reading'	=> 'I_AC_Power_SF',
    #       },

    "h40083" => {    # 40084 (Len 2) 40084 to 40085 AC Power
        'len'     => '2',                                                           #  I_AC_Power, I_AC_Power_SF
        'reading' => 'Block_AC_Power',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMppt($hash,$name,"I_AC_Power",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },

    #   	"h40085"	=>	{	# 40086 1 I_AC_Frequenz uint16 Hertz Frequenzwert
    #					'reading'	=> 'I_AC_Frequency',
    #          'format'		=> '%.f Hz',					# format string for sprintf
    #					'expr'	=> '$val/100',
    #          'setexpr'	=> '$val',
    # 			},
    #     "h40086"	=>	{	# 40086 1 I_AC_Frequency_SF uint16 Frequenz Skalierungsfaktor
    #					'reading'		=> 'I_AC_Frequency_SF',
    #				},

    "h40085" => {    # 40086 (Len 2) 40086 to 40087 AC Frequency
        'len'     => '2',                                                               # I_AC_Frequency, I_AC_Frequency_SF
        'reading' => 'Block_AC_Frequency',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMppt($hash,$name,"I_AC_Frequency",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },

    #     "h40087"	=>	{	#
    #					'reading'	=> 'I_AC_VA',
    #				},
    #    "h40088"	=>	{	#
    #				'reading'		=> 'I_AC_VA_SF',
    #			},

    "h40087" => {    # 40088 (Len 2) 40088 to 40089 Apparent Power (Scheinleistung)
        'len'     => '2',                                                        # I_AC_VA,  I_AC_VA_SF
        'reading' => 'Block_AC_VA',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMppt($hash,$name,"I_AC_VA",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },

    #     "h40089"	=>	{	#
    #				'reading'	=> 'I_AC_VAR',
    #				},
    #     "h40090"	=>	{	#
    #					'reading'		=> 'I_AC_VAR_SF',
    #				},

    "h40089" => {    # 40090 (Len 2) 40090 to 40091 Reactive Power (Blindleistung)
        'len'     => '2',                                                         # I_AC_VAR, I_AC_VAR_SF
        'reading' => 'Block_AC_VAR',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMppt($hash,$name,"I_AC_VAR",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },

    #     "h40091"	=>	{	#
    #					'reading'	=> 'I_AC_PF',
    #				},
    #    "h40092"	=>	{	#
    #					'reading'		=> 'I_AC_PF_SF',
    #				},

    "h40091" => {    # 40090 (Len 2) 40090 to 40091 Power Factor (Leistungsfaktor)
        'len'     => '2',                                                        #I_AC_PF, I_AC_PF_SF
        'reading' => 'Block_AC_PF',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMppt($hash,$name,"I_AC_PF",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },

    #    "h40093" =>  {
    #               'expr' => '$val / 1000',
    #             'format' => '%.2f kWh',
    #                'len' => '2',
    #            'reading' => 'I_AC_Energie_WH_kWh',
    #             'unpack' => 'l>',
    #                },
    #    "h40095"	=>	{	#
    #					'reading'		=> 'I_AC_Energy_WH_SF',
    #				},

    "h40093" => {    # 40094 (Len 3) 40094 to 40096 AC Lifetime Energy production
        'len'     => '3',                                                               #I_AC_Energy_WH (2), I_AC_Energy_WH_SF
        'reading' => 'Block_AC_Energy_WH',
        'unpack'  => 'l>s>',
        'expr'    => 'ExprMppt($hash,$name,"I_AC_Energy_WH",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },

    #     "h40096"	=>	{	#
    #					'reading'		=> 'I_DC_Current',
    #          'format'		=> '%.2f A',
    #				},
    #     "h40097"	=>	{	#
    #				'reading'		=> 'I_DC_Current_SF',
    #				},

    "h40096" => {    # 40097 (Len 2) 40097 to 40098 DC Current
        'len'     => '2',                                                             # I_DC_Current, I_DC_Current_SF
        'reading' => 'Block_DC_Current',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMppt($hash,$name,"I_DC_Current",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },

    #     "h40098"	=>	{	#
    #					'reading'		=> 'I_DC_Voltage',
    #          'format'		=> '%.2f V',
    #				},
    #     "h40099"	=>	{	#
    #					'reading'		=> 'I_DC_Voltage_SF',
    #				},

    "h40098" => {    # 40099(Len 2) 40099 to 40100 DC Voltage
        'len'     => '2',                                                             # I_DC_Voltage, I_DC_Voltage_SF
        'reading' => 'Block_DC_Voltage',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMppt($hash,$name,"I_DC_Voltage",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },

    #     "h100"	=>	{	#
    #					'reading'		=> 'I_DC_Power',
    #          'format'		=> '%.2f W',
    #				},
    #     "h40101"	=>	{	#
    #					'reading'		=> 'I_DC_Power_SF',
    #				},

    "h40100" => {    # 400101(Len 2) 400101 to 40102 DC Power
        'len'     => '2',                                                           # I_DC_Power, I_DC_Power_SF
        'reading' => 'Block_DC_Power',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMppt($hash,$name,"I_DC_Power",$val[0],$val[1],0,0,0)',    # conversion of raw value to visible value
    },
    "h40103" => {                                                                   # 40104 1 I_Temp_Sink int16 Grad Celsius Kühlkörpertemperatur
        'reading' => 'I_Temp_HeatSink',                                             # name of the reading for this value
        'format'  => '%.f °C',                                                     # format string for sprintf
        'expr'    => '$val/100',
        'setexpr' => '$val',
    },
    "h40107" => {                                                                   # 40108 1 I_Status uint16 Betriebszustand
        'reading' => 'I_Status',                                                    # name of the reading for this value
        'expr'    => '$val',
        'map' =>
'1:Off, 2:Sleeping Night mode, 3:Grid Monitoring, 4:Inverter is ON and producing power, 5:Production(curtailed), 6:Shutting down, 7:Fault, 8:Maintenance',
        'setexpr' => '$val',
    },

    # Ende parseInfo
);

my %SolarEdgeMeter1parseInfo = (
###############################################################################################################
    # Holding Register
###############################################################################################################
    #C_SunSpec_ID ignored
    "h40121" => {    # 40121 Value = 0x0001. Uniquely identifies this as a SunSpec Common Model Block
        'reading' => 'X_Meter_1_C_SunSpec_DID_0',
        'type'    => 'VT_String',
    },
    "h40122" => {    # 40122 65 = Length of block in 16-bit registers
        'reading' => 'X_Meter_1_C_SunSpec_Length',
        'type'    => 'VT_String',
    },
    "h40123" => {    # 40123 16 C_Manufacturer String(32) Meter manufacturer
        'reading' => 'X_Meter_1_C_Manufacturer',
        'type'    => 'VT_String',
    },
    "h40139" => {    # 40139 16 C_Model String(32) Meter model
        'reading' => 'X_Meter_1_Block_C_Model',
        'type'    => 'VT_String',
        'expr'    => 'ExprMeter($hash,$name,"X_Meter_1_C_Model",$val[0],0,0,0,0,0,0,0,0)',    # conversion of raw value to visible value
    },
    "h40155" => {    # 40155 16 C_Option String(16) Meter Option  Export + Import, Production, consumption,
        'reading' => 'X_Meter_1_C_Option',
        'type'    => 'VT_String',
    },
    "h40163" => {    # 40163 16 C_Version String(16) Meter version
        'reading' => 'X_Meter_1_C_Version',
        'type'    => 'VT_String',
    },
    "h40171" => {    # 40171 16 C_Version String(16) Meter SN
        'reading' => 'X_Meter_1_C_SerialNumber',
        'type'    => 'VT_String',
    },
    "h40187" => {    # 40187 16 C_Version String(16) Inverter Modbus ID ?
        'reading' => 'X_Meter_1_C_DeviceAddress',
        'defPoll' => '0',
        'poll'    => 'once',
    },
    "h40188" => {    # 40188 1 C_SunSpec_DID uint16 SunSpecMODBUS
                     # Map:
                     #  Single Phase (AN or AB) Meter (201)
                     #  Split Single Phase (ABN) Meter (202)
                     #  Wye-Connect Three Phase (ABCN) Meter (203)
                     #  Delta-Connect Three Phase (ABC) Meter(204)
        'reading' => 'X_Meter_1_C_SunSpec_DID',    # name of the reading for this value
        'len'     => '1',
        'map'  => '201:single phase, 202:split single phase, 203:wye-connect three phase, 204:delta-connect three phase meter',
        'poll' => 'once',
    },
    "h40190" => {                                  # 40190 (Len 5) 40190 to 40194
        'len'     => '5',                            #M_AC_Current, M_AC_Current_A(L1), M_AC_Current_B(L2), M_AC_Current_C(L3), M_AC_Current_SF
        'reading' => 'X_Meter_1_Block_AC_Current',
        'unpack'  => 'nnnns>', # 's>s>s>s>n!', # 's>s>s>s>s>'
        'expr' => 'ExprMeter($hash,$name,"X_Meter_1_M_AC_Current",$val[0],$val[1],$val[2],$val[3],$val[4],0,0,0,0)'
        ,                                            # conversion of raw value to visible value
    },
    
     "h40195" => {    #  #Line to Neutral AC Voltage (average of activephases) 40195 to 40203
        'len' => '9',    #M_AC_Voltage_LN, M_AC_Voltage_AN, M_AC_Voltage_BN, M_AC_Voltage_CN, M_AC_Voltage_LL, M_AC_Voltage_AB, M_AC_Voltage_BC, M_AC_Voltage_CA, M_AC_Voltage_SF  
        'reading' => 'X_Meter_1_Block_AC_Voltage',
        'unpack'  => 'nnnnnnnns>', # 'NNNNNNNNs>',
        'expr'    => 'ExprMeter($hash,$name,"X_Meter_1_M_AC_Voltage",$val[0],$val[1],$val[2],$val[3],$val[4],$val[5],$val[6],$val[7],$val[8])'
        ,                 # conversion of raw value to visible value
    },
    
    #"h40195" => {                                    #Line to Neutral AC Voltage (average of activephases)
    #    'reading' => 'X_Meter_1_M_AC_Voltage_LN',
    #    'expr'    => '$val/100',
    #    'setexpr' => '$val',
    #},
    #"h40196" => {                                    #Phase A to Neutral AC Voltage
    #    'reading' => 'X_Meter_1_M_AC_Voltage_AN',
    #    'expr'    => '$val/100',
    #    'setexpr' => '$val',
    #},
    #"h40197" => {                                    #Phase B to Neutral AC Voltage
    #    'reading' => 'X_Meter_1_M_AC_Voltage_BN',
    #    'expr'    => '$val/100',
    #    'setexpr' => '$val',
    #},
    #"h40198" => {                                    #Phase C to Neutral AC Voltage
    #    'reading' => 'X_Meter_1_M_AC_Voltage_CN',
    #    'expr'    => '$val/100',
    #    'setexpr' => '$val',
    #},
    #"h40199" => {                                    # 40199 (Len 5) 40199 to 40202
    #    'len'     => '5',                               #M_AC_Voltage_LL, M_AC_Voltage_AB, M_AC_Voltage_BC, M_AC_Voltage_CA, M_AC_Voltage_SF,
    #    'reading' => 'X_Meter_1_Block_AC_Voltage_LL',
    #    'unpack'  => 'nnnns>',
    #    'expr' => 'ExprMeter($hash,$name,"X_Meter_1_M_AC_Voltage",$val[0],$val[1],$val[2],$val[3],$val[4],0,0,0,0)'
    #    ,                                               # conversion of raw value to visible value
    #},
    
    "h40204" => {                                       # 40086 (Len 2) 40086 to 40087 AC Frequency
        'len'     => '2',                                                                                  # M_AC_Freq, M_AC_Freq_SF
        'reading' => 'X_Meter_1_Block_AC_Frequency',
        'unpack'  => 'ns>',
        'expr'    => 'ExprMeter($hash,$name,"X_Meter_1_M_AC_Frequency",$val[0],$val[1],0,0,0,0,0,0,0)',    # conversion of raw value to visible value
    },

    "h40206" => {                                                                                          #Real Power 40206 (Len 5) 40206 to 40210
        'len'     => '5',                          #M_AC_Power, M_AC_Power_A, M_AC_Power_B, M_AC_Power_C, M_AC_Power_SF,
        'reading' => 'X_Meter_1_Block_AC_Power',
        'unpack'  => 's>s>s>s>n!', # 'nnnns>', #'s>s>s>s>n!',  # 's>s>s>s>s>' 
        'expr' =>
          'ExprMeter($hash,$name,"X_Meter_1_M_AC_Power",$val[0],$val[1],$val[2],$val[3],$val[4],0,0,0,0)',  # conversion of raw value to visible value
    },

    "h40211" => {    #Apparent Power 40211 (Len 5) 40211 to 40215
        'len'     => '5',                       #M_AC_VA, M_AC_VA_A, M_AC_VA_B, M_AC_VA_C, M_AC_VA_SF,
        'reading' => 'X_Meter_1_Block_AC_VA',
        'unpack'  => 's>s>s>s>n!',
        'expr' =>
          'ExprMeter($hash,$name,"X_Meter_1_M_AC_VA",$val[0],$val[1],$val[2],$val[3],$val[4],0,0,0,0)',    # conversion of raw value to visible value
    },
    "h40216" => {    #Reactive Power 40216 (Len 5) 40215 to 40220
        'len'     => '5',                        #M_AC_VAR, M_AC_VAR_A, M_AC_VAR_B, M_AC_VAR_C, M_AC_VAR_SF,
        'reading' => 'X_Meter_1_Block_AC_VAR',
        'unpack'  => 's>s>s>s>n!',
        'expr' =>
          'ExprMeter($hash,$name,"X_Meter_1_M_AC_VAR",$val[0],$val[1],$val[2],$val[3],$val[4],0,0,0,0)',    # conversion of raw value to visible value
    },
    "h40221" => {    # Power Factor h40221 (Len 5)   40221 to 40225
        'len'     => '5',                       #M_AC_PF, M_AC_PF_A, M_AC_PF_B, M_AC_PF_C, M_AC_PF_SF,
        'reading' => 'X_Meter_1_Block_AC_PF',
        'unpack'  =>  's>s>s>s>n!', 
        'expr' =>
          'ExprMeter($hash,$name,"X_Meter_1_M_AC_PF",$val[0],$val[1],$val[2],$val[3],$val[4],0,0,0,0)',    # conversion of raw value to visible value
    },

    "h40226" => {    #Accumulated Energy Real Energy 40226 to 40242
        'len' => '17',    #M_Exported, M_Exported_A, M_Exported_B, M_Exported_C, M_Imported, M_Imported_A, M_Imported_B, M_Imported_C, M_Energy_W_SF
        'reading' => 'X_Meter_1_Block_Energy_W',
        'unpack'  => 'L>L>L>L>L>L>L>L>s>', # 'l>l>l>l>l>l>l>l>s>'  
        'expr'    => 'ExprMeter($hash,$name,"X_Meter_1_M_Energy_W",$val[0],$val[1],$val[2],$val[3],$val[4],$val[5],$val[6],$val[7],$val[8])'
        ,                
    },

   "h40243" => {         #Apparent Energy Real Energy 40243 to 40259
       'len' => '17',    #M_Exported, M_Exported_A, M_Exported_B, M_Exported_C, M_Imported, M_Imported_A, M_Imported_B, M_Imported_C, M_Energy_W_SF
       'reading' => 'X_Meter_1_Block_Energy_VA',
       'unpack'  => 'L>L>L>L>L>L>L>L>s>',
       'expr'    => 'ExprMeter($hash,$name,"X_Meter_1_M_Energy_VA",$val[0],$val[1],$val[2],$val[3],$val[4],$val[5],$val[6],$val[7],$val[8])'
        ,                
    },
);
#####################################
my %SolarEdgeBat1parseInfo = (
###############################################################################################################
    # Holding Register
###############################################################################################################
    "h57600" => {    # E100(F500) 16R Battery 1 Manufacturer Name String[32]
        'reading' => 'Battery_1_Manufacturer_Name',
        'type'    => 'VT_String',
    },
    "h57616" => {    # E110(F510) 16R Battery 1 Model String[32]
        'reading' => 'Battery_1_Model',
        'type'    => 'VT_String',
    },
    "h57632" => {     # E120(F520) 16R Battery 1 Firmware Version String[32]
        'reading' => 'Battery_1_Firmware',
        'type'    => 'VT_String',
    },
    "h57648" => {     # E130(F530) 16R Battery 1 SerialNumber String[32]
        'reading' => 'Battery_1_SerialNumber',
        'type'    => 'VT_String',
    },
    "h57664" => {    # E140(F540) 1R Battery 1 DeviceID Uint16
        'len'     => '1',                                                           
        'reading' => 'Battery_1_DeviceID',
    },
    "h57666" => {    # E142 (F542) 2R Battery 1 Rated Energy Float32 W*H
        'len'     => '2',                                                           
        'reading' => 'Battery_1_Rated_Energy_WH',
        'unpack'  => 'L>',  # 'NN' , 'D>'
    },
    "h57668" => {    # E144 (F544) 2R Battery 1 Max Charge Continues Power Float32 W
        'len'     => '2',                                                           
        'reading' => 'Battery_1_Max_Charge_Continues_Power_W',
        'unpack'  => 'L>',
    },
    "h57670" => {    # E146 (F546) 2R Battery 1 Max Discharge Continues Power Float32 W
        'len'     => '2',                                                           
        'reading' => 'Battery_1_Max_Discharge_Continues_Power_W',
        'unpack'  => 'L>',
    },
    "h57672" => {    # E148 (F548) 2R Battery 1 Max Charge Peak Power Float32 W
        'len'     => '2',                                                           
        'reading' => 'Battery_1_Max_Charge_Peak_Power_W',
        'unpack'  => 'L>',  # 'DD'
    },
    "h57674" => {    # E14A (F54A) 2R Battery 1 Max Discharge Peak Power Float32 W
        'len'     => '2',                                                           
        'reading' => 'Battery_1_Max_Discharge_Peak_Power_W',
        'unpack'  => 'L>',   #'I2 '
    },
    "h57712" => {     # E170(F570) 2R Battery 1 Instantaneous Voltage Float32 V
        'len'     => '2',  
        'reading' => 'Battery_1_Instantaneous_Voltage_V',
        'unpack'  => 'L>',  #'d2'
    },
    "h57714" => {     # E172(F572) 2R Battery 1 Instantaneous Current Float32 A
        'len'     => '2',  
        'reading' => 'Battery_1_Instantaneous_Current_A',
        'unpack'  => 'L>',  #'dd'
    },
    "h57716" => {     # E174(F574) 2R Battery 1 Instantaneous Power Float32  W
        'len'     => '2',  
        'reading' => 'Battery_1_Instantaneous_Power_W',
        'unpack'  => 'L>',
    },
    "h57734" => {     # E186(F586) 2R Battery 1 Status Uint32 0-7
        'len'     => '2',  
        'reading' => 'Battery_1_Status',
        'expr'    => '$val',
        'map'     => '1:Aus, 3:Laden, 4:Entladen, 6:Erhaltungsladen',   # 1: Aus 3: Laden 4: Entladen 6: Erhaltungsladen
        'setexpr' => '$val',
    },
);
#####################################



#####################################
sub Initialize()
{
    my $hash = shift;

    my %SolarEdgeparseInfoAll = ( %SolarEdgeparseInfo, %SolarEdgeMeter1parseInfo, %SolarEdgeBat1parseInfo );

    #require "$attr{global}{modpath}/FHEM/98_Modbus.pm";
    #require "$attr{global}{modpath}/FHEM/DevIo.pm";
   
    
    #$hash->{DefFn} = \&Define;
    #$hash->{AttrFn}     = \&Attr;
    $hash->{parseInfo}  = \%SolarEdgeparseInfoAll;    # defines registers for this Modbus Defive
    $hash->{deviceInfo} = \%SolarEdgedeviceInfo;      # defines properties of the device like
    ModbusLD_Initialize($hash);        # Generic function of the Modbus module does the rest
    #Modbus::InitializeLD($hash);                      # Generic function of the Modbus module does the rest

    $hash->{AttrList} =
        $hash->{AttrList}
      . "X_PV_Energy X_PV_EnergyToday X_PV_EnergyCurrentWeek X_PV_EnergyCurrentMonth X_Calculated_Consumption X_M_ExportedToday X_M_ExportedCurrentWeek X_M_ExportedCurrentMonth X_M_ImportedToday X_M_ImportedCurrentWeek X_M_ImportedCurrentMonth"
      . "$readingFnAttributes" . " "
      .                                               # Standard Attributes like IODEv etc
      $hash->{ObjAttrList} . " " .                    # Attributes to add or overwrite parseInfo definitions
      $hash->{DevAttrList} . " " .                    # Attributes to add or overwrite devInfo definitions
      "poll-.*" . " " .                               # overwrite poll with poll-ReadingName
      "polldelay-.*" . " " .                          # overwrite polldelay with polldelay-ReadingName
      "errorHandlingOf" . " ";                        # overwrite polldelay with polldelay-ReadingName

      return;
}
###################################
sub ExprMppt()
{                                                     # Berechnung Wert mit ScaleFactor unter Beachtung Operating_State

    #	Expr, conversion of raw value to visible value
    my @vval;
    my $hash        = shift;                          # Übergabe Geräte-Hash
    my $DevName     = shift;                          # Übergabe Geräte-Name
    my $ReadingName = shift;
    $vval[0] = shift;
    $vval[1] = shift;
    $vval[2] = shift;
    $vval[3] = shift;
    $vval[4] = shift;

    # Register
    my @SolarEdge_readings =
      ( "I_AC_Current", "I_AC_Power", "I_AC_VA", "I_AC_VAR", "I_AC_PF", "I_AC_Energy_WH", "I_DC_Current", "I_DC_Voltage", "I_DC_Power" );
    my ( $Psec, $Pmin, $Phour, $Pmday, $Pmonth, $Pyear, $Pwday, $Pyday, $Pisdst ) = localtime( time() + 61 );
    my $Pyear2 = $Pyear + 1900;

    Log3 $hash, 4, "SolarEdge $DevName : " . $vval[0] . " Reg :" . $ReadingName;
    
     my $WertNeu =
        @vval . " "
      . $vval[0] . " "
      . $vval[1] . " "
      . $vval[2] . " "
      . $vval[3] . " "
      . $vval[4] ;
    
        if ( $ReadingName eq "C_Model" )
    {
        Log3 $hash, 4, "SolarEdge $DevName Model : " . $vval[0] . ":" . $vval[1] . ":" . $vval[2] . ":" . $vval[3] . ":" . $vval[4];
        $hash->{MODEL_WR} = $vval[0];
        $hash->{MODEL} = $vval[0];
        readingsBulkUpdate( $hash, $ReadingName, $vval[0] );
    }
    elsif ( $ReadingName eq "I_AC_Current" )
    {
        readingsBulkUpdate( $hash, $ReadingName,         $vval[0] * 10**$vval[4] );
        readingsBulkUpdate( $hash, $ReadingName . "_A",  $vval[1] * 10**$vval[4] );
        readingsBulkUpdate( $hash, $ReadingName . "_B",  $vval[2] * 10**$vval[4] );
        readingsBulkUpdate( $hash, $ReadingName . "_C",  $vval[3] * 10**$vval[4] );
        readingsBulkUpdate( $hash, $ReadingName . "_SF", $vval[4] );
    }
    elsif ( $ReadingName eq "I_AC_Power" || $ReadingName eq "I_DC_Power" )
    {
        my $POWER = ( $vval[0] * 10**$vval[1] );
        Log3 $hash, 4, "SolarEdge I_Power_0 : " . $vval[0] . " POWER :" . $POWER;

        if ( $POWER < 0 || $POWER > 18000 )
        {
            $POWER = 0;
        }

        Log3 $hash, 4, "SolarEdge I_Power_1 : " . $vval[0] . " POWER :" . $POWER;
        readingsBulkUpdate( $hash, $ReadingName,         $POWER );
        readingsBulkUpdate( $hash, $ReadingName . "_SF", $vval[1] );

    }
    elsif ( $ReadingName eq "I_AC_Energy_WH" )
    {
        # Anfang I_AC_Energy_WH (Today, Week,...)
        my $energy_pv   = ReadingsVal( $DevName, "X_PV_Energy", -1 );
        my $energy_time = $vval[0] * 10**$vval[1];

        if ( $energy_pv <= 0 )
        {

            readingsBulkUpdate( $hash, "X_PV_EnergyToday", "0" );
        }
        else
        {
            my $ts_energy_today = ReadingsTimestamp( $DevName, "X_PV_EnergyToday", 0 );
            my $energy_today    = ReadingsVal( $DevName, "X_PV_EnergyToday", 0 );

            my $time_now = TimeNow();
            my $date_now = substr( $time_now, 0, 10 );

            my $reading_month = substr( $ts_energy_today, 5, 2 );
            my $reading_date  = substr( $ts_energy_today, 0, 10 );

            Log3 $hash, 4, "SolarEdge TimeStamp PV-Energie: $ts_energy_today : D1: $reading_date : $time_now :  $date_now ";
            Log3 $hash, 4, "SolarEdge Jahr Monat PV-Energie: $reading_month : " . "PV_" . ($Pyear2) . "_" . ( $Pmonth + 1 ) . " ----";

            if ( $date_now eq $reading_date )
            {
                # Prüfung gleicher Tag
                #Same Day
                readingsBulkUpdate( $hash, "X_PV_EnergyToday", $energy_today + ( $energy_time - $energy_pv ) );
            }
            else
            {
                #Next Day
                my $energy_week = ReadingsVal( $DevName, "X_PV_EnergyCurrentWeek", 0 );

                readingsBulkUpdate( $hash, "X_PV_EnergyCurrentWeek", $energy_week + $energy_today );

                if ( ( $Pmonth + 1 ) eq $reading_month )
                {
                    # Prüfung gleicher Monat
                    #Same Month
                    my $energy_month = ReadingsVal( $DevName, "X_PV_EnergyCurrentMonth", 0 );

                    readingsBulkUpdate( $hash, "X_PV_EnergyCurrentMonth", $energy_month + $energy_today );
                }
                else
                {
                    # Next Month
                    my $energy_month = ReadingsVal( $DevName, "X_PV_EnergyCurrentMonth", 0 );

                    readingsBulkUpdate( $hash, "PV_" . ($Pyear2) . "_" . ($Pmonth), $energy_month );
                    readingsBulkUpdate( $hash, "X_PV_EnergyCurrentMonth",           "0" );
                }

                # New Day start at 0 again
                readingsBulkUpdate( $hash, "X_PV_EnergyToday", "0" );

                Log3 $hash, 4, "SolarEdge PV-Energie: $energy_today :  $energy_time : $energy_pv  ";
            }
        }

        readingsBulkUpdate( $hash, $ReadingName,         $vval[0] * 10**$vval[1]  );
        readingsBulkUpdate( $hash, "X_PV_Energy",        $vval[0] * 10**$vval[1]  );
        readingsBulkUpdate( $hash, $ReadingName . "_SF", $vval[1] );

       
       
       
        # Ende  I_AC_Energy_WH(Today, Week,...
    }
    else
    {
        readingsBulkUpdate( $hash, $ReadingName,         $vval[0] * 10**$vval[1] );
        readingsBulkUpdate( $hash, $ReadingName . "_SF", $vval[1] );
    }

     ############## Tabelle in STATE aufbauen ################
        my $wr_status = ReadingsVal( $DevName, "I_Status", 0 );
        my $temp = ReadingsVal( $DevName, "I_Temp_HeatSink", 0 );
        my $a_power = ReadingsVal( $DevName, "I_AC_Power", 0 );
        my $d_power = ReadingsVal( $DevName, "I_DC_Power", 0 );
        my $s_dc_voltage = ReadingsVal( $DevName, "I_DC_Voltage", 0 );
        my $s_ac_current = ReadingsVal( $DevName, "I_AC_Current", 0 );
        my $s_ac_energy = ReadingsVal( $DevName, "I_AC_Energy_WH", 0 );
        my $einheit_e = "Wh";
        
        if  ($s_ac_energy > 1000000)
        {
          $einheit_e = "MWh";
          $s_ac_energy = nearest('0.01',$s_ac_energy / 1000000);   
        } elsif ( $s_ac_energy > 1000) {
          $einheit_e = "kWh";
          $s_ac_energy = nearest('0.01',$s_ac_energy / 1000);
        }
        my $energie = $s_ac_energy." ".$einheit_e;
        my $s_teil_1 = "<table border=0 bordercolor='green' cellspacing=0 align='center'><tr><th><h1>Gesamtenergie ".$energie." </h1> </td></tr></table>";
        my $s_teil_2 = "<table border=4 bordercolor='green' cellspacing=5 align='center'><tr><th>Status</th><th>Temperatur</th><tr><td>".$wr_status."</td><td>".$temp."</td></tr>";
        my $s_teil_3 = "<tr><th>Leistung DC</th><th>Leistung AC</th><th>Spannung DC</th><th>Strom AC</th></tr><tr><td>".$d_power." W</td><td>".$a_power." W</td><td>".$s_dc_voltage." V-</td><td>". $s_ac_current." A~</td></tr></table>";
	#	my $state ="<h1>Gesamtenergie ".$energie." </h1><table border=4 bordercolor='green' cellspacing=5 frame=box><tr><th>Leistung DC</th><th>Leistung AC</th><th>Spannung DC</th><th>Strom AC</th></tr><tr><td>".$d_power." W</td><td>".$a_power." W</td><td>".$s_dc_voltage." V-</td><td>". $s_ac_current." A~</td></tr></table>";
    #   my $state = "<h1>Gesamtenergie ".$energie." </h1><table border=1 bordercolor='green' cellspacing=1><tr><th>Status: ".$wr_status." </th><th>Temperatur: ".$temp." </th></tr><table><tr><th></th></tr><table border=4 bordercolor='green' cellspacing=5 frame=box><tr><th>Leistung DC</th><th>Leistung AC</th><th>Spannung DC</th><th>Strom AC</th></tr><tr><td>".$d_power." W</td><td>".$a_power." W</td><td>".$s_dc_voltage." V-</td><td>". $s_ac_current." A~</td></tr></table>";
        my $state = $s_teil_1.$s_teil_2.$s_teil_3 ;
		readingsBulkUpdate($hash, "state", $state);
       ###############################################


    #if ( $ReadingName eq "I_AC_Power" )
    #{
    #    HelperConsumption( $hash, $DevName );
    #}

    Log3 $hash, 4, "SolarEdge $DevName : " . $WertNeu;
    return $WertNeu;
}

###################################
sub ExprMeter()
{    # Berechnung Wert mit ScaleFactor unter Beachtung Operating_State

    #	Expr, conversion of raw value to visible value
    my @vval;
    my $hash        = shift;    # Übergabe Geräte-Hash
    my $DevName     = shift;    # Übergabe Geräte-Name
    my $ReadingName = shift;
    $vval[0] = shift;
    $vval[1] = shift;
    $vval[2] = shift;
    $vval[3] = shift;
    $vval[4] = shift;
    $vval[5] = shift;
    $vval[6] = shift;
    $vval[7] = shift;
    $vval[8] = shift;

    # Register
    my ( $Psec, $Pmin, $Phour, $Pmday, $Pmonth, $Pyear, $Pwday, $Pyday, $Pisdst ) = localtime( time() + 61 );
    my $Pyear2 = $Pyear + 1900;

    #my ($Psec,$Pmin,$Phour,$Pmday,$Pmonth,$Pyear,$Pwday,$Pyday,$Pisdst) = localtime(TimeNow());
    my $time_now = TimeNow();
    my $date_now = substr( $time_now, 0, 10 );

    Log3 $hash, 4, "SolarEdge $DevName : " . $vval[0] . " Reg :" . $ReadingName;
    my $WertNeu =
        @vval . " "
      . $vval[0] . " "
      . $vval[1] . " "
      . $vval[2] . " "
      . $vval[3] . " "
      . $vval[4] . " "
      . $vval[5] . " "
      . $vval[6] . " "
      . $vval[7] . " "
      . $vval[8];

    if ( $ReadingName eq "X_Meter_1_C_Model" )
    {
        Log3 $hash, 4, "SolarEdge $DevName X_Meter_1_C_Model : " . $vval[0] . ":" . $vval[1];
        
        if (length($vval[0]) > 4 ) {
            my $model_wr =  ReadingsVal( $DevName, "C_Model", 0 );
            $hash->{MODEL_METER} = $vval[0];
           # $hash->{MODEL_WR} = $model_wr;
            $hash->{MODEL} = $model_wr." : ".$vval[0];                  # MODEL      SE7K-RWS48BNN4 : SE-MTR-3Y-400V-A
            readingsBulkUpdate( $hash, $ReadingName, $vval[0] );
        }        
        
    }
    elsif ($ReadingName eq "X_Meter_1_M_AC_Current"
        || $ReadingName eq "X_Meter_1_M_AC_Power"
        || $ReadingName eq "X_Meter_1_M_AC_VA"
        || $ReadingName eq "X_Meter_1_M_AC_VAR"
        || $ReadingName eq "X_Meter_1_M_AC_PF" )
    {
        readingsBulkUpdate( $hash, $ReadingName,         $vval[0] * 10**$vval[4] );
        readingsBulkUpdate( $hash, $ReadingName . "_A",  $vval[1] * 10**$vval[4] );
        readingsBulkUpdate( $hash, $ReadingName . "_B",  $vval[2] * 10**$vval[4] );
        readingsBulkUpdate( $hash, $ReadingName . "_C",  $vval[3] * 10**$vval[4] );
        readingsBulkUpdate( $hash, $ReadingName . "_SF", $vval[4] );
    }
    elsif ( $ReadingName eq "X_Meter_1_M_AC_Voltage" )    #M_AC_Voltage_LN, M_AC_Voltage_AN, M_AC_Voltage_BN, M_AC_Voltage_CN, M_AC_Voltage_LL, M_AC_Voltage_AB, M_AC_Voltage_BC, M_AC_Voltage_CA, M_AC_Voltage_SF  
    {
        readingsBulkUpdate( $hash, $ReadingName . "_LN", $vval[0] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_AN", $vval[1] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_BN", $vval[2] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_CN", $vval[3] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_LL", $vval[4] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_AB", $vval[5] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_BC", $vval[6] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_CA", $vval[7] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_SF", $vval[8] );
    }
    elsif ( $ReadingName eq "X_Meter_1_M_Energy_W" )
    {
        # Anfang EXPORTED
        my $energy_exported   = ReadingsVal( $DevName, "X_Meter_1_M_Exported", -1 );
        my $exported_time       = $vval[0] * 10**$vval[8]; ## New Value X_Meter_1_M_Exported

        if ( $energy_exported <= 0 )
        {
            readingsBulkUpdate( $hash, "X_M_ExportedToday", "0" );
        }
        else
        {
            my $ts_exported_today = ReadingsTimestamp( $DevName, "X_M_ExportedToday", 0 );
            my $exported_today    = ReadingsVal( $DevName, "X_M_ExportedToday", 0 );

            my $time_now = TimeNow();
            my $date_now = substr( $time_now, 0, 10 );

            my $reading_month = substr( $ts_exported_today, 5, 2 );
            my $reading_date  = substr( $ts_exported_today, 0, 10 );

            Log3 $hash, 4, "SolarEdge TimeStamp PV-Exported: $ts_exported_today : D1: $reading_date : $time_now :  $date_now ";
            Log3 $hash, 4, "SolarEdge Jahr Monat PV-Exported: $reading_month : " . "PV_" . ($Pyear2) . "_" . ( $Pmonth + 1 ) . " ----";

            if ( $date_now eq $reading_date )
            {
                # Prüfung gleicher Tag
                #Same Day
                readingsBulkUpdate( $hash, "X_M_ExportedToday", $exported_today + ( $exported_time - $energy_exported ) );
            }
            else
            {
                #Next Day
                my $exported_week = ReadingsVal( $DevName, "X_M_ExportedCurrentWeek", 0 );

                readingsBulkUpdate( $hash, "X_M_ExportedCurrentWeek", $exported_week + $exported_today );

                if ( ( $Pmonth + 1 ) eq $reading_month )
                {
                    # Prüfung gleicher Monat
                    #Same Month
                    my $exported_month = ReadingsVal( $DevName, "X_M_ExportedCurrentMonth", 0 );

                    readingsBulkUpdate( $hash, "X_M_ExportedCurrentMonth", $exported_month + $exported_today );
                }
                else
                {
                    # Next Month
                    my $exported_month = ReadingsVal( $DevName, "X_M_ExportedCurrentMonth", 0 );

                    readingsBulkUpdate( $hash, "X_M_Exported_" . ($Pyear2) . "_" . ($Pmonth), $exported_month );
                    readingsBulkUpdate( $hash, "X_M_ExportedCurrentMonth",           "0" );
                }

                # New Day start at 0 again
                readingsBulkUpdate( $hash, "X_M_ExportedToday", "0" );

                Log3 $hash, 4, "SolarEdge PV-Exported: $exported_today :  $exported_time : $energy_exported  ";
            }
        }
        # Ende EXPORTED

        # Anfang IMPORTED
        my $energy_imported   = ReadingsVal( $DevName, "X_Meter_1_M_Imported", -1 );
        my $imported_time     = $vval[4] * 10**$vval[8]; ## New Value X_Meter_1_M_Imported

        if ( $energy_imported <= 0 )
        {
            readingsBulkUpdate( $hash, "X_M_ImportedToday", "0" );
        }
        else
        {
            my $ts_imported_today = ReadingsTimestamp( $DevName, "X_M_ImportedToday", 0 );
            my $imported_today    = ReadingsVal( $DevName, "X_M_ImportedToday", 0 );

            my $time_now = TimeNow();
            my $date_now = substr( $time_now, 0, 10 );

            my $reading_month = substr( $ts_imported_today, 5, 2 );
            my $reading_date  = substr( $ts_imported_today, 0, 10 );

            Log3 $hash, 4, "SolarEdge TimeStamp PV-Imported: $ts_imported_today : D1: $reading_date : $time_now :  $date_now ";
            Log3 $hash, 4, "SolarEdge Jahr Monat PV-Imported: $reading_month : " . "PV_" . ($Pyear2) . "_" . ( $Pmonth + 1 ) . " ----";

            if ( $date_now eq $reading_date )
            {
                # Prüfung gleicher Tag
                #Same Day
                readingsBulkUpdate( $hash, "X_M_ImportedToday", $imported_today + ( $imported_time - $energy_imported ) );
            }
            else
            {
                #Next Day
                my $imported_week = ReadingsVal( $DevName, "X_M_ImportedCurrentWeek", 0 );

                readingsBulkUpdate( $hash, "X_M_ImportedCurrentWeek", $imported_week + $imported_today );

                if ( ( $Pmonth + 1 ) eq $reading_month )
                {
                    # Prüfung gleicher Monat
                    #Same Month
                    my $imported_month = ReadingsVal( $DevName, "X_M_ImportedCurrentMonth", 0 );

                    readingsBulkUpdate( $hash, "X_M_ImportedCurrentMonth", $imported_month + $imported_today );
                }
                else
                {
                    # Next Month
                    my $imported_month = ReadingsVal( $DevName, "X_M_ImportedCurrentMonth", 0 );

                    readingsBulkUpdate( $hash, "X_M_Imported_" . ($Pyear2) . "_" . ($Pmonth), $imported_month );
                    readingsBulkUpdate( $hash, "X_M_ImportedCurrentMonth",           "0" );
                }

                # New Day start at 0 again
                readingsBulkUpdate( $hash, "X_M_ImportedToday", "0" );

                Log3 $hash, 4, "SolarEdge PV-Imported: $imported_today :  $imported_time : $energy_imported  ";
            }
        }
        # Ende IMPORTED
        # Energy Consumption kwh

        #my $energy_pv = ReadingsVal( $DevName, "I_AC_Energy_WH", -1 );
        #All Time Consumption
        #my $consumption_time = ($energy_pv - $energy_exported) + $energy_imported;

        my $imported_today = ReadingsVal( $DevName, "X_M_ImportedToday", 0 );
        my $exported_today = ReadingsVal( $DevName, "X_M_ExportedToday", 0 );
        my $pv_today       = ReadingsVal( $DevName, "X_PV_EnergyToday",  0 );

        #Consumption Today
        my $consumption_today = ($pv_today - $exported_today) +  $imported_today;

        #readingsBulkUpdate( $hash, "X_Calculated_Consumption_kWh", $consumption_time / 1000 );
        readingsBulkUpdate( $hash, "X_M_ConsumptionToday", $consumption_today );

        #Calc First then Update
        readingsBulkUpdate( $hash, "X_Meter_1_M_Exported",   $vval[0] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Exported_A", $vval[1] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Exported_B", $vval[2] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Exported_C", $vval[3] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Imported",   $vval[4] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Imported_A", $vval[5] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Imported_B", $vval[6] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Imported_C", $vval[7] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_SF",     $vval[8] );
    }
    elsif ( $ReadingName eq "X_Meter_1_M_Energy_VA" )
    {
        readingsBulkUpdate( $hash, "X_Meter_1_M_Exported_VA",   $vval[0] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Exported_VA_A", $vval[1] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Exported_VA_B", $vval[2] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Exported_VA_C", $vval[3] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Imported_VA",   $vval[4] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Imported_VA_A", $vval[5] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Imported_VA_B", $vval[6] * 10**$vval[8] );
        readingsBulkUpdate( $hash, "X_Meter_1_M_Imported_VA_C", $vval[7] * 10**$vval[8] );
        readingsBulkUpdate( $hash, $ReadingName . "_SF",        $vval[8] );
    }
    else
    {
        readingsBulkUpdate( $hash, $ReadingName,         $vval[0] * 10**$vval[1] );
        readingsBulkUpdate( $hash, $ReadingName . "_SF", $vval[1] );
    }

    #if ( $ReadingName eq "X_Meter_1_M_AC_Power" )
    #{
    #     HelperConsumption( $hash, $DevName );
    #}

    Log3 $hash, 4, "SolarEdge $DevName : " . $WertNeu;
    return $WertNeu;
}

sub HelperConsumption()
{
    my $hash    = shift;    # Übergabe Geräte-Hash
    my $DevName = shift;    # Übergabe Geräte-Name

    my $powerInverter = ReadingsVal( $DevName, "I_AC_Power",           -1 );
    my $powerGrid     = ReadingsVal( $DevName, "X_Meter_1_M_AC_Power", -1 );
    my $consumption   = $powerGrid + $powerInverter;

    # Power from grid is negativ (1 - (-1) ) = 2
    $consumption = $powerInverter - $powerGrid;

    readingsBulkUpdate( $hash, "X_Calculated_Consumption", $consumption );
    return;

}

1;

=pod
=begin html

<a name="SolarEdge"></a>
<h3>SolarEdge</h3>
<ul>
    SolarEdge uses the low level Modbus module to provide a way to communicate with SolarEdge inverter.
	It defines the modbus input and holding registers and reads them in a defined interval.
  Modbusversion => Modbus 4.1.5 - 17.9.2019

  you may need to install the Math::Round module
  
  sudo apt install libmath-round-perl

	<br>
    <b>Prerequisites</b>
    <ul>
        <li>
          This module requires the basic Modbus module which itsef requires Device::SerialPort or Win32::SerialPort module.
        </li>
    </ul>
    <br>

    <a name="SolarEdgeDefine"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; SolarEdge &lt;Id&gt; &lt;Interval&gt; &lt;IP&gt; &lt;Mode&gt; </code>
        <br><br>
        The module connects to the smart electrical meter with Modbus Id &lt;Id&gt; through an already defined modbus device and actively requests data from the
        smart electrical meter every &lt;Interval&gt; seconds <br>
        <br>
        Example:<br>
        <br>
        <ul><code>define SEdge SolarEdge 1 60</code></ul>
        <ul><code>define SEdge SolarEdge 3 60 192.168.0.23:502 RTU</code></ul>
    </ul>
    <br>

    <a name="SolarEdgeConfiguration"></a>
    <b>Configuration of the module</b><br><br>
    <ul>
    apart from the modbus id and the interval which both are specified in the define command there is nothing that needs to be defined.
		However there are some attributes that can optionally be used to modify the behavior of the module. <br><br>
    The attributes that control which messages are sent / which data is requested every &lt;Interval&gt; seconds are:
    if the attribute is set to 1, the corresponding data is requested every &lt;Interval&gt; seconds. If it is set to 0, then the data is not requested.
   </ul>

    <a name="SolarEdgeSet"></a>
    <b>Set-Commands</b><br>
    <ul>
        The following set options are available:  none
    </ul>
	<br>
    <a name="SolarEdgeGet"></a>
    <b>Get-Commands</b><br>
    <ul>
        All readings are also available as Get commands. Internally a Get command triggers the corresponding
        request to the device and then interprets the data and returns the right field value.
    </ul>
	<br>
    <a name="SolarEdgeattr"></a>
    <b>Attributes</b><br><br>
    <ul>
	    <li><a href="#do_not_notify">do_not_notify</a></li>
      <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
        <br>
		  <li><b>X_PV_Energy</b></li>
		  <li><b>X_PV_EnergyToday</b></li>
      <li><b>X_PV_EnergyCurrentWeek</b></li>
		  <li><b>pv_energytomonth</b></li>
      <li><b>X_Calculated_Consumption</b> current power consumption (photovoltaik and / or grid)</li>
    </ul>
    <br>
</ul>

=end html
=cut
