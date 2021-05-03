#cd /tmp && curl https://dataverse.harvard.edu/api/access/datafiles/1375005 flights.zip && unzip flights.zip && bunzip flights.bz2

library(largeScaleR)
debug(register)
init("config")

cols <- c("Year"="integer","Month"="integer","DayofMonth"="integer",
	  "DayOfWeek"="integer","DepTime"="integer","CRSDepTime"="integer",
	  "ArrTime"="integer","CRSArrTime"="integer",
	  "UniqueCarrier"="character","FlightNum"="integer","TailNum"="character",
	  "ActualElapsedTime"="integer","CRSElapsedTime"="integer",
	  "AirTime"="integer","ArrDelay"="integer", "DepDelay"="integer",
	  "Origin"="character","Dest"="character","Distance"="integer",
	  "TaxiIn"="integer","TaxiOut"="integer", "Cancelled"="integer",
	  "CancellationCode"="character","Diverted"="integer",
	  "CarrierDelay"="integer","WeatherDelay"="integer","NASDelay"="integer",
	  "SecurityDelay"="integer","LateAircraftDelay"="integer")

flights <- read(localCSV("/tmp/1987flights.csv", header=TRUE, colTypes = cols), max.size=1024^2)
flights
preview(flights)
desc(flights)
host(flights)

isMondayFlights <- flights$DayOfWeek == 1L
sum(isMondayFlights)
mondayFlights <- subset(flights, isMondayFlights)
length(mondayFlights)

cancelledMondays <- table(mondayFlights$Month, mondayFlights$Cancelled)

final()