## libraries

library(rvest)
library(dplyr)
library(data.table)
library(janitor)
library(stringr)


# official dictionary -----------------------------------------------------

## letters
base_url <- "https://psz.praca.gov.pl/rynek-pracy/bazy-danych/klasyfikacja-zawodow-i-specjalnosci/wyszukiwarka-opisow-zawodow//-/klasyfikacja_zawodow/litera/A"
litery <- read_html(base_url) %>% 
  html_nodes("div.job-classification_letter-navigation > span > a") %>%
  html_attr("href")

## links to specific occupancies

opisy_linki <- lapply(litery, function(x) {
  x %>%
    read_html() %>%
    html_nodes("table.job-classification_search-results.results-grid") %>%
    html_nodes("a") %>%
    html_attr("href")
})

opisy_linki <- unlist(opisy_linki)

## scraping descriptions

opisy_zawodow <- lapply(opisy_linki, function(x) {x %>%
    read_html() %>%
    html_table() %>%
    .[[1]] %>%
    rename(koluma = X1, opis = X2)}
)

## transforming

opisy_zawodow <- bind_rows(opisy_zawodow, .id = "strona")
opisy_zawodow <- setDT(opisy_zawodow)
opisy_zawodow[, koluma:=tolower(koluma)]
opisy_zawodow[, koluma:=gsub("\\:", "", koluma)]
opisy_zawodow[, koluma:=gsub(" ", "_", koluma)]
opisy_zawodow <- opisy_zawodow[str_detect(koluma, "^(nazwa|kod|liczba_odwiedzin|synteza|zadania_zawodowe|dodatkowe_zadania_zawodowe)$")]
opisy_zawodow[strona %in% opisy_zawodow[opis == "Opis w opracowaniu"]$strona & koluma == "nazwa", ]
opisy_zawodow[koluma == "kod", zawod:=opis]
opisy_zawodow[, zawod := na.omit(unique(zawod)), by=strona]
opisy_zawodow_wide <- dcast(opisy_zawodow, zawod ~ koluma, value.var = "opis")
opisy_zawodow_wide <- opisy_zawodow_wide[,.(zawod, nazwa, synteza, zadania_zawodowe, dodatkowe_zadania_zawodowe)]
opisy_zawodow_wide <- opisy_zawodow_wide[order(zawod)]


# more info from infodoradca+ ---------------------------------------------


## get links to infodoradca

more_info <- sapply(1:length(opisy_linki), function(x) {
  print(x)
  opisy_linki[x]  %>%
    read_html() %>%
    html_node("div.read-more > a" ) %>%
    html_attr("href") 
})

more_info_full <- na.omit(more_info)
more_info_full <- paste0("https://psz.praca.gov.pl",more_info_full)


opisy_1000 <- list()

k <- 1
for (i in more_info_full) {
  opisy_1000[[k]] <- read_html(i) %>%
    html_nodes("div.occupation-details") %>%
    html_nodes("div.characteristic") %>%
    html_nodes("div.description > blok > sekcja") %>%
    html_text() %>%
    str_replace_all("\\n|\\t", " ") %>%
    .[c(1, 2, 5, 6, 9, 12, 13:15)] %>%
    trimws()
  k <- k + 1
  if (k %% 10 ==0) print(k)
  
}


opisy_1000_df <- do.call('rbind',opisy_1000)
opisy_1000_df <- as.data.frame(opisy_1000_df)
opisy_1000_df <- setDT(opisy_1000_df)



setnames(opisy_1000_df, 
         names(opisy_1000_df),
         c("kod_zawodu", "synonimy", "synteza", "opis_pracy", "wyksztalcenie", 
           "zadania", "kompetencja1", "kompetencja2", "kompetencja3"))

opisy_1000_df[, kod_zawodu:=str_extract(kod_zawodu, "\\d{6}")]
opisy_1000_df[, opis_pracy:=str_replace(opis_pracy, "Opis pracy ", "")]

opisy_1000_df[, wyksztalcenie:=str_remove(wyksztalcenie, "Wykształcenie niezbędne do podjęcia pracy w zawodzie ")]
opisy_1000_df[, wyksztalcenie:=str_remove(wyksztalcenie, "Obecnie \\(\\d{4} r\\.\\) ")]
opisy_1000_df[, zadania:=str_remove(zadania, "Pracownik w ")]
opisy_1000_df[, kompetencja1:=str_remove(kompetencja1, "Kompetencja zawodowa Kz\\d{1}\\: ")]
opisy_1000_df[, kompetencja2:=str_remove(kompetencja2, "Kompetencja zawodowa Kz\\d{1}\\: ")]
opisy_1000_df[, kompetencja3:=str_remove(kompetencja3, "Kompetencja zawodowa Kz\\d{1}\\: ")]

opisy_1000_df[str_detect(synonimy, "Nie wyst"), synonimy:=""]

opisy_1000_df[, desc1 := paste(synonimy, synteza)]
opisy_1000_df[, desc2 := opis_pracy]
opisy_1000_df[, desc3 := wyksztalcenie]
opisy_1000_df[, desc4 := zadania]
opisy_1000_df[, desc5 := kompetencja1]
opisy_1000_df[, desc6 := kompetencja2]
opisy_1000_df[, desc7 := kompetencja3]


opisy_1000_long <- melt(data = opisy_1000_df[,.(kod_zawodu, desc1,desc2,desc3,desc4,desc5,desc6,desc7)],
                        id.vars = "kod_zawodu",
                        measure.vars = paste0("desc", 1:7),
                        value.name = "desc")
setnames(opisy_1000_long, "kod_zawodu", "class")

