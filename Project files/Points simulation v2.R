
library(dplyr)
library(reshape2)
library(ggplot2)
library(parallel)
library(data.table)

# Get functions
source('GetFPLData.R')
source('getOdds.R')
source('./Dreamteam/Dreamteam - recursive v2.R')

# Get club lookup
clubs <- fread('./Project files/club lookup.csv')

# Get fantasybet prices
fb <- fread('./Project files/Fantasybet - gw32.csv', encoding = "UTF-8") %>%
  mutate(fname = ifelse(grepl(",", Player), substr(Player, nchar(Player), nchar(Player)), ""),
         web_name = ifelse(grepl(",", Player), substr(Player, 1, nchar(Player) - 3), Player)) %>%
  inner_join(clubs, by = c("Club"="club"))

# Filter fpl data
fpl.4 <- fpl.3 %>%
  left_join(select(fb, web_name, team, now_cost), by = c('web_name', 'team')) %>%
  mutate(now_cost = now_cost.y*10)

# Check who's missing
View(filter(arrange(fpl.4, desc(form)), is.na(now_cost.y)))

# Get dreamteams
dt <- list()
dt[[1]] <- dreamteam(fpl.4)
dt[[2]] <- dreamteam(filter(fpl.4, !id %in% dt[[1]]$element))
dt[[3]] <- dreamteam(filter(fpl.4, !id %in% dt[[1]]$element, !id %in% dt[[2]]$element))

dt[[1]]
dt[[2]]
dt[[3]]

# Check all expected points
for (i in 1:length(dt)) print(sum(dt[[i]][1:11, 'xp']))

# Match on all details
teamdetails <- lapply(1:length(dt), function(i) inner_join(dt[[i]], fpl.3, by = c('element'='id')))

# Simulate points for each player
teamsim <- lapply(1:length(dt), function(i) rowSums(do.call(cbind, lapply(teamdetails[[i]]$element[1:11], pointssim, teamdetails[[i]]))))

# Visualise probabilities
teamsim[[3]] %>%
  as.data.frame %>%
  ggplot(aes(x=`.`)) +
  geom_histogram(fill = 'dodgerblue3', color = 'dodgerblue4', bins = 30)

# # Stats
for (i in 1:length(dt)) print(mean(teamsim[[i]]))

# Get probability of each possible number of points
weights <- lapply(1:length(dt), function(i) as.numeric(table(teamsim[[i]])/length(teamsim[[i]])))

# This generates a score randomly according to the distrubtion of total points
sample(unique(teamsim[[1]]), 1, prob=weights[[1]], replace = TRUE)

# Sim function
pointsim <- function(y, maxent, n, compdat) {
  
  # Your points
  dtp = round(sapply(1:maxent, function(i) sample(unique(teamsim[[i]]), 1, prob=weights[[i]], replace = TRUE)), 0)
  
  results <- sapply(1:nrow(compdat), function(i) {
    
    # Generate other points. Assume they're as good as your best team.
    pts <- round(sample(unique(teamsim[[1]]), compdat$entries[i], prob=weights[[1]], replace = TRUE),0)
    
    # Get return
    r <- prizes[[i]][rank(-append(dtp,pts), ties.method = "first")[1:maxent]]
    r <- ifelse(is.na(r), 0, r) - compdat$fees[i]
    r <- sum(r)
    r
  })
  
  # Format as data frame
  results = data.frame(t(results))
  
  # Headers
  names(results) <- paste0(compdat$comps, ' x', maxent)
  
  if(y %% 50 == 0) print(paste('Processed', y, 'of', n))
  
  return(results)
}

