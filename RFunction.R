library('move')
library('foreach')
library('maptools')
library('lubridate')

rFunction <- function(data, maxspeed=NULL, duration=NULL, radius=NULL)
{
  Sys.setenv(tz="GMT")
  
  n.all <- length(timestamps(data))
  data <- data[!duplicated(paste0(round_date(timestamps(data), "5 min"), trackId(data))),]
  logger.info(paste0("For better performance, the data have been thinned to max 5 minute resolution. From the total ",n.all," positions, the algorithm retained ",length(timestamps(data))," positions for calculation."))

  if (is.null(maxspeed))
  {
    logger.info("You have not selected a maximum speed to filter out positions in flight. These positions are therefore kept in the data set, but might corrupt the result (do they?).")
    data.ground <- data
  } else
  {
    data.split <- move::split(data)
    data.ground <- foreach(datai = data.split) %do% {
      ix <- which(speed(datai)<maxspeed)
      res <- datai[sort(unique(c(ix,ix+1))),] #this would use the speed between positions
      #datai[datai@data$ground_speed<maxspeed] # this used the GPS ground speed at positions
    }
    names(data.ground) <- names(data.split)
    data.ground <- moveStack(data.ground[unlist(lapply(data.ground, length) > 0)])
  }
  
  if (is.null(duration) & is.null(radius)) logger.info("You didnt provide any roost site radius or minimum roost duration. Please go back and configure them. Here return input data set.") 
  if (is.null(duration) & !is.null(radius)) 
    {
    logger.info(paste0("You have selected a roost site radius of ",radius,"m, but no minimum roost duration. We here use 1h by default. If that is not what you need, please go back and configure the parameters."))
    duration <- 1
    }
  if (!is.null(duration) & is.null(radius))
    {
    logger.info(paste0("You have selected a minimum roost duration of ",duration,"h, but no roost site radius. We here use 1000m = 1km by default. If that is not what you need, please go back and configure the parameters."))
    radius <- 1000
  }
  
  # select night positions (use data.ground)
  data.ground.split <- move::split(data.ground)
  data.night <- foreach(data.groundi = data.ground.split) %do% {
    #print(namesIndiv(data.groundi))
    sunup <- data.frame(sunriset(coordinates(data.groundi), timestamps(data.groundi), direction="sunrise", POSIXct.out=TRUE))$time
    sundownx <- data.frame(sunriset(coordinates(data.groundi), timestamps(data.groundi), direction="sunset", POSIXct.out=TRUE))$time + 1800
    data.groundi@data <- cbind(data.groundi@data,sunup,sundownx)

    # there are no sunup or sundown during Arctic summer, then NA: here take out positions
    ix <- which(is.na(sunup) | is.na(sundownx))
    if (length(ix)>0)
    {
      logger.info(paste0("The data set of individual ",namesIndiv(data.groundi)," includes positions above/below the Arctic/Antarctic circle, so there are no sunup or sundown events during some time of the year. The relevant ",length(ix)," positions are taken out for the calculations."))
      data.groundi <- data.groundi[!is.na(sunup) & !is.na(sundownx),]
    }
    data.nighti <- data.groundi[timestamps(data.groundi)<=data.groundi$sunup | timestamps(data.groundi)>=data.groundi$sundownx,]
    year <- as.POSIXlt(timestamps(data.nighti))$year+1900
    yday <- as.POSIXlt(timestamps(data.nighti))$yday
    ynight <- yday
    ynight[timestamps(data.nighti)>data.nighti$sundownx] <- ynight[timestamps(data.nighti)>data.nighti$sundownx]+1
    
    # adapt for New Year's Eve
    year[as.POSIXlt(timestamps(data.nighti))$mday==31 & as.POSIXlt(timestamps(data.nighti))$mon==11 & timestamps(data.nighti)>data.nighti$sundownx] <- year[as.POSIXlt(timestamps(data.nighti))$mday==31 & as.POSIXlt(timestamps(data.nighti))$mon==11 & timestamps(data.nighti)>data.nighti$sundownx]+1
    ynight[as.POSIXlt(timestamps(data.nighti))$mday==31 & as.POSIXlt(timestamps(data.nighti))$mon==11 & timestamps(data.nighti)>data.nighti$sundownx] <- 0
    
    data.nighti@data <- cbind(data.nighti@data,year,yday,ynight)
    return(data.nighti)
  }
  names (data.night) <- names(data.ground.split)
  data.night.nozero <- data.night[unlist(lapply(data.night, length) > 0)]

  if (length(data.night.nozero)==0) 
  {
    logger.info("Your data contain no night positions. No csv overview saved. Return NULL.")
    result <- NULL
  } else 
  {
    data.night <- moveStack(data.night.nozero)
    
    # save all roost positions if is roost by given definition (radius, duration), goes backwards for last night roost
    data.night.split <- move::split(data.night)
    prop.roost.df <- data.frame("local.identifier"=character(),"year"=numeric(),"ynight"=numeric(),"timestamp.first"=character(),"timestamp.last"=character(),"roost.mean.long"=numeric(),"roost.mean.lat"=numeric(),"roost.nposi"=numeric(),"roost.duration"=numeric(),"roost.radius"=numeric())
    
    data.roost <- foreach(data.nighti = data.night.split) %do% {
      print(namesIndiv(data.nighti))
      data.roosti.df <- as.data.frame(data.nighti)[0,]
      
      year <- unique(data.nighti@data$year)
      for (k in seq(along=year))
      {
        data.nightik <- data.nighti[data.nighti@data$year==year[k],]
        night <- unique(data.nightik@data$ynight)
        for (j in seq(along=night))
        {
          data.nightikj <- data.nightik[data.nightik@data$ynight==night[j],]
          last <- Nikj <- length(data.nightikj)
          while (last>1) # as long as first night position is not the last
          {
            backdt <- as.numeric(difftime(timestamps(data.nightikj)[last],timestamps(data.nightikj)[-c(last:Nikj)],units="hours"))
            if (length(backdt)>=1) #changed this to allow for further away position (if in radius assume not moved), allows for worse resolution data
            {
              if (any(backdt<=duration)) data.sel <- data.nightikj[c(which(backdt<=duration),last),] else data.sel <- data.nightikj[(last-1):last,]
              m <- colMeans(coordinates(data.sel))
              dp0 <- distVincentyEllipsoid(m,coordinates(data.sel))
              p0 <- coordinates(data.sel)[min(which(dp0==max(dp0))),]
              dp1 <- distVincentyEllipsoid(p0,coordinates(data.sel))
              p1 <- coordinates(data.sel)[min(which(dp1==max(dp1))),]
              maxdist <- distVincentyEllipsoid(p0,p1)
              
              if (maxdist<radius)
              {
                ## check if already longer at this roost
                mid <- midPoint(p0,p1)
                data.bef <- data.nightikj[which(backdt>duration),]
                if (length(data.bef)>=1)
                {
                  dist.bef <- distVincentyEllipsoid(mid,coordinates(data.bef))
                  if (any(dist.bef>radius)) data.selx <- data.nightikj[c(which(backdt>duration)[-(1:max(which(dist.bef>radius)))],which(backdt<=duration),last),] else data.selx <- data.nightikj[c(which(backdt>duration),which(backdt<=duration),last),]
                } else data.selx <- data.sel
                
                data.selx.df <- as.data.frame(data.selx)
                
                time0 <- min(timestamps(data.selx))
                timeE <- max(timestamps(data.selx))
                durx <- as.numeric(difftime(timeE,time0,unit="hour"))
                radx <- max(distVincentyEllipsoid(mid,coordinates(data.selx)))
                
                if (durx>=duration & radx<=radius) #added this condition to only show roosts of given duraiton (if this condition is left out also roosts with shorter duration are given back)
                {
                  data.roosti.df <- rbind(data.roosti.df,data.selx.df)
                  prop.roost.df <- rbind(prop.roost.df,data.frame("local.identifier"=namesIndiv(data.selx),"year"=data.selx.df$year[1],"ynight"=data.selx.df$ynight[1],"timestamp.first"=as.character(time0),"timestamp.last"=as.character(timeE),"roost.mean.long"=mid[1,1],"roost.mean.lat"=mid[1,2],"roost.nposi"=length(data.selx),"roost.duration"=durx,"roost.radius"=radx))
                }
 
                break
              } else last <- last-1 #shift one time step
            } else last <- last-1 # shift one time step also if not enough data in previous Xh time frame
          }
        }
      }
      if (dim(data.roosti.df)[1]>0) data.roosti <- move(x=data.roosti.df$location_long,y=data.roosti.df$location_lat,time=data.roosti.df$timestamp,data=data.roosti.df,sensor=data.roosti.df$sensor,animal=data.roosti.df$local_identifier) else data.roosti <- NULL
    }
    names(data.roost) <- names(data.night.split)
    data.roost.nozero <- data.roost[unlist(lapply(data.roost, length) > 0)] #remove IDs with no data
    
    if (length(data.roost.nozero)==0) 
    {
      logger.info("Your output file contains no positions. No csv overview saved. Return NULL.")
      result <- NULL
    } else 
    {
      result <- moveStack(data.roost.nozero)
      write.csv(prop.roost.df,file = paste0(Sys.getenv(x = "APP_ARTIFACTS_DIR", "/tmp/"),"roost_overview.csv"),row.names=FALSE) #csv artefakt
      #write.csv(prop.roost.df,file = "roost_overview.csv",row.names=FALSE)
    }
  }

  return(result)
}

  
  
  
  
  
  
  
  
  
  
