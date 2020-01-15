Objective:
==========
check.build.avaibility.pl is a tool to check the avaibility and check times of specific exports to dropzone for a build done in a site (check the 'xxx_copy_done' file).
For the moment, Build.pl create a copy_done for : bin, packages, patches & deploymentunits.
The time format setted in ini file(s) is 24:00 (no am/pm)

Note:
=====
Its is not to check a build transferred by NSF/GRS.

Contact:
========
Bruno FABLET

Site Owner: Lev BuildOps

scripts:
	check.build.avaibility.pl

platform:
	windows
		
configs:
	$Site.ini (e.g.: Walldorf.ini)

requirements:
	perl installed
	build done and exported on local site with a xxx_copy_done file
