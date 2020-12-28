# SolarEdge FHEM-Modul

28.12.2020 

SolarEdge uses the low level Modbus module to provide a way to communicate with SolarEdge inverter.
It defines the modbus input and holding registers and reads them in a defined interval.
Modbusversion => Modbus 4.3.8 - 25.12.2020      !!!!!!!!!      ---> https://forum.fhem.de/index.php/topic,75638.msg1114110.html#msg1114110

Update in FHEM:

update all https://raw.githubusercontent.com/pejonp/FHEM---SolarEdge/master/controls_SolarEdge.txt


When your devices are successfully created, please call

		fheminfo send

to be part of the anonymous device statistics. (Search for SplarEdge to see models, that are already in use.)

So I have the chance to see if new devices must be supported.

		attr global sendStatistics onUpdate

must set.

you may need to install the Math::Round module

 		sudo apt install libmath-round-perl
