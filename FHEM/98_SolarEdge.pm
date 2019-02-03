##############################################
# $Id: 98_SolarEdge.pm 0013 2019-02-03 22:00:00Z pejonp $
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
# 2018-10-29  pv_energy pv_energytoday pv_energytoweek pv_energytomont ...

#defmod SEdge SolarEdge 3 60 192.168.2.7:20108 RTU

package main;

use strict;
use warnings;
use Time::Local;

sub SolarEdge_Initialize($);
sub SolarEdge_Define($$);		# wird beim 'define' von AESGI-Protokoll Gerät aufgerufen
sub SolarEdge_Notify($$);		# wird beim 'Notify' vom Device aufgerufen
sub ExprMppt($$$$$$$$);				# Berechnung Wert mit ScaleFactor unter Beachtung Operating_State

my $SolarEdge_Version = '0001 - 16.10.2018';

my %SolarEdgedeviceInfo = (
    "h" =>  { 
        'combine' => '30',
        'defPoll' => '1',   
    },
    "type-VT_String" =>  {  
        'decode' => 'cp850',
        'encode' => 'utf8',
          'expr' => '$val =~ s/[\00]+//gr',
           'len' => '8',
       'revRegs' => '0',
        'unpack' => 'a16',
     'poll' => 'once',  # only poll once after define (or after a set)
    },
    "type-VT_String4" =>  { 
        'decode' => 'cp850',
        'encode' => 'utf8',
        'expr' => '$val =~ s/[\00]+//gr',
        'len' => '4',
        'revRegs' => '0',
        'unpack' => 'a8',
    },
);


my %SolarEdgeparseInfo = (
###############################################################################################################
# Holding Register
###############################################################################################################
          "h40000" =>  {  # 40001 2 C_SunSpec_ID uint32 Wert = "SunS" (0x53756e53). Identifiziert dies eindeutig als eine SunSpec Modbus-Karte
                                   'len' => '2',
                               'reading' => 'C_SunSpec_ID',
                               'revRegs' => '0',
                                'unpack' => 'a4',
                                  'poll' => 'once',
                       },
          "h40004" =>  { # 40005 16 C_Hersteller String(32) Bei SunSpec eingetragener Wert = " SolarEdge "
                               'reading' => 'C_Manufacturer',
                                  'type' => 'VT_String',
                                                 },
          "h40020" =>  {       'reading' => 'Block_C_Model',
                                  'type' => 'VT_String',
                                  'expr' => 'ExprMppt($hash,$name,"C_Model",$val[0],0,0,0,0)',	# conversion of raw value to visible value
                       },
          "h40044" =>  {       'reading' => 'C_Version',
                                  'type' => 'VT_String',
                       },
          "h40052" =>  {       'reading' => 'C_SerialNumber',
                                  'type' => 'VT_String',
                       },
          "h40068" =>  {	#
                     					'reading'  => 'C_DeviceAddress',
                               'defPoll' => '0',
                                  'poll' => 'once',
                       },
          "h40069" =>	{	# 40070 1 C_SunSpec_DID uint16 101 = Einphasig 102 = Spaltphase1 103 = Dreiphasig
                     					'reading'	=> 'C_SunSpec_DID',			# name of the reading for this value
                        				  'len' => '1' ,
                                  'map' => '101:Einphasig, 102:Spaltphase1, 103:Dreiphasig',
                                 'poll' => 'once',
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
     "h40071" =>  {     # 40076 1 I_AC_Strom_SF uint16 AC-Strom Skalierungsfaktor
        'len' => '5',
    'reading' => 'Block_AC_Current',
     'unpack' => 'nnnns>',
       'expr' => 'ExprMppt($hash,$name,"I_AC_Current",$val[0],$val[1],$val[2],$val[3],$val[4])',	# conversion of raw value to visible value
                  },
     "h40076"	=>	{	#
    'reading' => 'I_AC_VoltageAB',
				},
     "h40077"	=>	{	#
    'reading' => 'I_AC_VoltageBC',
				},
     "h40078" =>	{	#
    'reading' => 'I_AC_VoltageCA',
				},
     "h40079"	=>	{	#
    'reading' => 'I_AC_VoltageAN',
				},
     "h40080"	=>	{	#
    'reading'	=> 'I_AC_VoltageBN',
				},
     "h40081"	=>	{	#
    'reading' => 'I_AC_VoltageCN',
				},
     "h40082"	=>	{	#
    'reading' => 'I_AC_Voltage_SF',
				},
  #  "h40083"	=>	{	# 40084 1 I_AC_Leistung int16 Watt AC-Leistungswert
	#				'reading'	=> 'I_AC_Power',
  #        },
  #  "h40084"	=>	{	#
	#				'reading'	=> 'I_AC_Power_SF',
  #       },
     "h40083" =>  {
        'len' => '2',
    'reading' => 'Block_AC_Power',
     'unpack' => 'ns>',
       'expr' => 'ExprMppt($hash,$name,"I_AC_Power",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
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
     "h40085" =>  {
        'len' => '2',
    'reading' => 'Block_AC_Frequency',
     'unpack' => 'ns>',
       'expr' => 'ExprMppt($hash,$name,"I_AC_Frequency",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
                  },  
#     "h40087"	=>	{	#
#					'reading'	=> 'I_AC_VA',
#				},
#    "h40088"	=>	{	#
#				'reading'		=> 'I_AC_VA_SF',
#			},
     "h40087" =>  {
        'len' => '2',
    'reading' => 'Block_AC_VA',
     'unpack' => 'ns>',
       'expr' => 'ExprMppt($hash,$name,"I_AC_VA",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
                  },
#     "h40089"	=>	{	#
#				'reading'	=> 'I_AC_VAR',
#				},
#     "h40090"	=>	{	#
#					'reading'		=> 'I_AC_VAR_SF',
#				},
     "h40089" =>  {
              'len' => '2',
          'reading' => 'Block_AC_VAR',
           'unpack' => 'ns>',
             'expr' => 'ExprMppt($hash,$name,"I_AC_VAR",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
                  },
#     "h40091"	=>	{	#
#					'reading'	=> 'I_AC_PF',
#				},
#    "h40092"	=>	{	#
#					'reading'		=> 'I_AC_PF_SF',
#				},
     "h40091" =>  {
              'len' => '2',
          'reading' => 'Block_AC_PF',
           'unpack' => 'ns>',
             'expr' => 'ExprMppt($hash,$name,"I_AC_PF",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
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
     "h40093" =>  {
              'len' => '3',
          'reading' => 'Block_AC_Energy_WH',
           'unpack' => 'l>s>',
             'expr' => 'ExprMppt($hash,$name,"I_AC_Energy_WH_kWh",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
                  },        
#     "h40096"	=>	{	#
#					'reading'		=> 'I_DC_Current',
#          'format'		=> '%.2f A',
#				},
#     "h40097"	=>	{	#
#				'reading'		=> 'I_DC_Current_SF',
#				},
     "h40096" =>  {
              'len' => '2',
          'reading' => 'Block_DC_Current',
           'unpack' => 'ns>',
             'expr' => 'ExprMppt($hash,$name,"I_DC_Current",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
                  },        
#     "h40098"	=>	{	#
#					'reading'		=> 'I_DC_Voltage',
#          'format'		=> '%.2f V',
#				},
#     "h40099"	=>	{	#
#					'reading'		=> 'I_DC_Voltage_SF',
#				},
     "h40098" =>  {
              'len' => '2',
          'reading' => 'Block_DC_Voltage',
           'unpack' => 'ns>',
             'expr' => 'ExprMppt($hash,$name,"I_DC_Voltage",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
                  },         
#     "h100"	=>	{	#
#					'reading'		=> 'I_DC_Power',
#          'format'		=> '%.2f W',
#				},
#     "h40101"	=>	{	#
#					'reading'		=> 'I_DC_Power_SF',
#				},
     "h40100" =>  {
              'len' => '2',
          'reading' => 'Block_DC_Power',
           'unpack' => 'ns>',
             'expr' => 'ExprMppt($hash,$name,"I_DC_Power",$val[0],$val[1],0,0,0)',	# conversion of raw value to visible value
                  },         
    "h40103"	=>	{	# 40104 1 I_Temp_Kühler int16 Grad Celsius Kühlkörpertemperatur
					'reading'		=> 'I_Temp_Kuehler',			# name of the reading for this value
          'format'		=> '%.f °C',					# format string for sprintf
					'expr'	=> '$val/100',
          'setexpr'	=> '$val',
				},
    "h40107"	=>	{	# 40108 1 I_Status uint16 Betriebszustand
					'reading'	=> 'I_Status',			# name of the reading for this value
					'expr'	=> '$val',
          'map' => '1:Aus, 2:Nachtmodus, 4:WR_An',
          'setexpr'	=> '$val',
				},

# Ende parseInfo
);


#####################################
sub
SolarEdge_Initialize($)
{
    my ($hash) = @_;

	  require "$attr{global}{modpath}/FHEM/98_Modbus.pm";
    require "$attr{global}{modpath}/FHEM/DevIo.pm";

    $hash->{DefFn}     = "SolarEdge_Define";
 #   $hash->{UndefFn}   = "SolarEdge_Undef";
 #   $hash->{ParseFn}   = "SolarEdge_Parse";
 #   $hash->{NotifyFn}   = "SolarEdge_Notify";
    $hash->{AttrFn}	 = "SolarEdge_Attr";
	  $hash->{parseInfo}  = \%SolarEdgeparseInfo;			# defines registers for this Modbus Defive
    $hash->{deviceInfo} = \%SolarEdgedeviceInfo;			# defines properties of the device like
	  ModbusLD_Initialize($hash);							# Generic function of the Modbus module does the rest

	  $hash->{AttrList} = $hash->{AttrList}
                            ."pv_energy pv_energytoday pv_energytoweek pv_energytomonth pv_energytoyear "
                            ."$readingFnAttributes"
                            . " " .		# Standard Attributes like IODEv etc
		$hash->{ObjAttrList} . " " .						# Attributes to add or overwrite parseInfo definitions
    $hash->{DevAttrList} . " " .                     # Attributes to add or overwrite devInfo definitions
        "poll-.*"." ".										# overwrite poll with poll-ReadingName
		    "polldelay-.*"." ".									# overwrite polldelay with polldelay-ReadingName
		    "errorHandlingOf"." ";                                   # overwrite polldelay with polldelay-ReadingName

}

###################################
sub ExprMppt($$$$$$$$)		{								# Berechnung Wert mit ScaleFactor unter Beachtung Operating_State
#	Expr, conversion of raw value to visible value
	my $hash			= $_[0];							# Übergabe Geräte-Hash
	my $DevName			= $_[1];						# Übergabe Geräte-Name
	my $ReadingName		= $_[2];
  my @vval;
 $vval[0]			= $_[3];
 $vval[1]			= $_[4];
 $vval[2]			= $_[5];
 $vval[3]			= $_[6];
 $vval[4]			= $_[7];

    # Register
    my @SolarEdge_readings=("I_AC_Current","I_AC_Power","I_AC_VA","I_AC_VAR","I_AC_PF","I_AC_Energy_WH_kWh","I_DC_Current","I_DC_Voltage","I_DC_Power");
    my ($Psec,$Pmin,$Phour,$Pmday,$Pmonth,$Pyear,$Pwday,$Pyday,$Pisdst) = localtime(time()+61);
    my $Pyear2 = $Pyear+1900;
    #my ($Psec,$Pmin,$Phour,$Pmday,$Pmonth,$Pyear,$Pwday,$Pyday,$Pisdst) = localtime(TimeNow());
    my $time_now = TimeNow();
    my $datum0 = substr($time_now,0,10);
 
    Log3 $hash, 4, "SolarEdge $DevName : ".$vval[0]." Reg :".$ReadingName;
    my $WertNeu = @vval." ".$vval[0]." ".$vval[1]." ".$vval[2]." ".$vval[3]." ".$vval[4] ;

  if ($ReadingName eq "C_Model") {
        Log3 $hash, 4, "SolarEdge $DevName Model : ".$vval[0].":".$vval[1].":".$vval[2].":".$vval[3].":".$vval[4];
        $hash->{MODEL} = $vval[0];
        readingsBulkUpdate($hash, $ReadingName,$vval[0]);
  } elsif ($ReadingName eq "I_AC_Current") {
        readingsBulkUpdate($hash, $ReadingName, $vval[0] * 10 ** $vval[4]);
        readingsBulkUpdate($hash, $ReadingName."L1", $vval[1] * 10 ** $vval[4]);
        readingsBulkUpdate($hash, $ReadingName."L2", $vval[2] * 10 ** $vval[4]);
        readingsBulkUpdate($hash, $ReadingName."L3", $vval[3] * 10 ** $vval[4]);
        readingsBulkUpdate($hash, $ReadingName."_SF", $vval[4]);
  } elsif ($ReadingName eq "I_AC_Power") {
        my $ACPOWER =   ($vval[0] * 10 ** $vval[1]);
         Log3 $hash, 4, "SolarEdge I_AC_Power_0 : ".$vval[0]." ACPOWER :".$ACPOWER;
        if ($ACPOWER < 0 || $ACPOWER > 15000){
          $ACPOWER = 0;
        }
         Log3 $hash, 4, "SolarEdge I_AC_Power_1 : ".$vval[0]." ACPOWER :".$ACPOWER;
        readingsBulkUpdate($hash, $ReadingName, $ACPOWER);
        readingsBulkUpdate($hash, $ReadingName."_SF", $vval[1]);
        
  } elsif ($ReadingName eq "I_AC_Energy_WH_kWh") {
        # Anfang I_AC_Energy_WH_kWh (Today, Week,...)
        my $energy_pv = ReadingsVal($DevName,$ReadingName,-1)*1000;
        my $ts_energy_today = ReadingsTimestamp($DevName,"pv_energytoday",0);
        # my ($Rsec,$Rmin,$Rhour,$Rmday,$Rmonth,$Ryear,$Rwday,$Ryday,$Risdst) = localtime($ts_energy_today);
        #  2018-10-29 15:33:00
        my $Rmonth = substr($ts_energy_today,5,2); 
        my $energy_today = ReadingsVal($DevName,"pv_energytoday",0);
        my $datum1 = substr($ts_energy_today,0,10);

        Log3 $hash, 4, "SolarEdge TimeStamp PV-Energie : $ts_energy_today : D1: $datum1 : $time_now :  $datum0 ";  
        Log3 $hash, 4, "SolarEdge Jahr Monat PV-Energie: $Rmonth : "."PV_".($Pyear2)."_".($Pmonth+1)." ----";      
        
        my $energy_time =   $vval[0] * 10 ** $vval[1];
        if ($energy_pv <= 0){
          readingsBulkUpdate($hash, "pv_energytoday", "0"); 
        }else{
           if ($datum0 eq $datum1 ){ # Prüfung gleicher Tag
              readingsBulkUpdate($hash, "pv_energytoday", $energy_today + ($energy_time - $energy_pv) );         
          } else {
              my $e_week = ReadingsVal($DevName,"pv_energytoweek",0);
              readingsBulkUpdate($hash, "pv_energytoweek", $e_week +$energy_today);  
              if ( ($Pmonth+1) eq $Rmonth){  # Prüfung gleicher Monat
                   my $e_month = ReadingsVal($DevName,"pv_energymonth",0);
                  readingsBulkUpdate($hash, "pv_energymonth",$e_month + $energy_today);
              } else {
                   my $e_month = ReadingsVal($DevName,"pv_energymonth",0);
                  readingsBulkUpdate($hash,"PV_".($Pyear2)."_".($Pmonth),$e_month);                   
                  readingsBulkUpdate($hash, "pv_energymonth","0");              
              }
              readingsBulkUpdate($hash, "pv_energytoday", "0");        
         }
      }
        readingsBulkUpdate($hash, $ReadingName, $energy_time / 1000) ;
        readingsBulkUpdate($hash, $ReadingName."_SF", $vval[1]);
      
        Log3 $hash, 4, "SolarEdge PV-Energie : $energy_today :  $energy_time : $energy_pv  ";
        # Ende  I_AC_Energy_WH_kWh (Today, Week,...)
  }else{
      readingsBulkUpdate($hash, $ReadingName, $vval[0] * 10 ** $vval[1]);
      readingsBulkUpdate($hash, $ReadingName."_SF", $vval[1]);
  } 

	Log3 $hash, 4, "SolarEdge $DevName : ".$WertNeu;
	return $WertNeu;
}

1;

=pod
=begin html

<a name="SolarEdge"></a>
<h3>SolarEdge</h3>
<ul>
    SolarEdge uses the low level Modbus module to provide a way to communicate with SolarEdge inverter.
	It defines the modbus input and holding registers and reads them in a defined interval.
  Modbusversion => 4.0.13 - 26.10.2018

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
		  <li><b>pv_energy</b></li>
		  <li><b>pv_energytoday</b></li>
      <li><b>pv_energytoweek</b></li>
		  <li><b>pv_energytomonth</b></li>
      <li><b>pv_energytoyear</b></li>
    </ul>
    <br>
</ul>

=end html
=cut
