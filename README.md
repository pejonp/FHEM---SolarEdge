# SolarEdge FHEM-Modul

08.03.2020 

SolarEdge uses the low level Modbus module to provide a way to communicate with SolarEdge inverter.
It defines the modbus input and holding registers and reads them in a defined interval.
Modbusversion => Modbus 4.1.5 - 17.9.2019

Update in FHEM:

update all https://raw.githubusercontent.com/pejonp/FHEM---SolarEdge/master/controls_SolarEdge.txt


When your devices are successfully created, please call

		fheminfo send

to be part of the anonymous device statistics. (Search for SplarEdge to see models, that are already in use.)

So I have the chance to see if new devices must be supported.

		attr global sendStatistics onUpdate

must set.
