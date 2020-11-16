# Roost Sites
MoveApps

Github repository: *github.com/movestore/RoostSites*

## Description
This App filters the data set to night positions with roosting behaviour (in a certain radius for a certain min time with low speed). The roosting positions are given as output and a csv table with properties of the roost sites of each individual is saved as artefact. 

## Documentation
This App extracts all locations of animals in a defined nightly roost site. It is closely linked to roosting behaviour of waterfowl for which night is defined as the time from sunset+30min until sunrise.

Before the analysis starts, the input data set is tinned to a resolution of max. 5 minutes to speed up the run time. It is sensible to do this, because high resolution data does not add anything to roost extraction, for which longer time ranges are required.

Then, the actualy analysis is done in three steps. First, all positions with speed above the provided maximum speed are remove. This is sensible, as roosting is a resing behaviour with little movement. Second, all (local) night positions are selected. For this, the sunriset() function from the maptools() package is used. If there are any locations in Arctic/Antarctic regions in times where there is no sunrise and sunset, those locations are removed, as roosting is not clearly defined then. Third, all positions that define a roost site with minimum duration and minimum radius are selected. For each individual and night only one roost site is selected, with priority to the one closest to sunrise.

Properties of detected roost sites are provided in a table that is given out as pdf artefact. There the following properties are listes for each roost site: animal name, year, night number, timestamp of first roost location, timestamp of last roost location, roost mean loation (longitute/latitude), number of locations in the roost, duration the animal has stayed in the roost, realised radius of the roost. 

### Input data
moveStack in Movebank format

### Output data
moveStack in Movebank format

### Artefacts
`roost_overview.csv`: csv-file with Table of roost site properites (see details in Documentatin above)

### Parameters 
`maxspeed`: Maximum instantaneous ground speed an animal is allowed during roost behaviour. Locations with GPS ground speeds above this value will be removed.

`duration`: Defined duration the animal minimally stays in a given radius for it to be considered roost. Unit: `hours`.

`radius`: Defined radius the animal has to stay in for a given duration of time for it to be considered roost. Unit: `metres`.

### Null or error handling:
**Parameter `maxspeed`:** If no maximum ground speed is provided (NULL), all locations are used for the night and roost analysis. This techniqually allows fast movement to be classified as roosting behaviour.

**Parameter `duration`:** If no duration AND no radius are given, the input data set is returned with a warning. If no duraiton is given (NULL), but a radius is defined then a default duration of 1 hour is set. 

**Parameter `radius`:** If no radius AND no duration are given, the input data set is returned with a warning. If no radius is given (NULL), but a duration is defined then a default radius of 1000m = 1km is set. 

**Data:** If there are no roosting locations retained after all analyses, NULL is returned, likely leading to an error.