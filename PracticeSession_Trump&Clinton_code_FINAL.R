################################################################################################
# Building an Interpretable NLP model to classify Trump & Clinton tweets Workshop
# full code 
# eRum 2018, Budapest 
################################################################################################


### loading packages ####

library(readr)
library(dplyr)
library(stringr)
library(lubridate)
library(ggplot2)
library(quanteda)
library(lime)

theme_set(theme_minimal()) # a bit biased preference...

#data prep
tweet_csv <- read_csv("tweets.csv")
str(tweet_csv, give.attr = FALSE)

## first look data exploration ####
sort(table(tweet_csv$original_author), decreasing = TRUE)
table(tweet_csv$is_retweet, is.na(tweet_csv$original_author))
table(tweet_csv$handle)
table(tweet_csv$handle, tweet_csv$is_retweet)
table(tweet_csv$lang)
table(tweet_csv$handle, tweet_csv$lang)



### data cleaning ####
tweet_data <- tweet_csv %>% 
  #  filter(is_retweet == "False") %>%
  select(author = handle,
         text,
         retweet_count,
         favorite_count,
         source_url,
         timestamp = time) %>% 
  mutate(date = as_date(str_sub(timestamp, 1, 10)),
         hour = hour(hms(str_sub(timestamp, 12, 19))),
         tweet_num = row_number()) %>% 
  select(-timestamp)


str(tweet_data)

#show the non-lengthy columns
tweet_data %>%
  select(-c(text, source_url)) %>%
  head()

### data formatting ####

### show what tokenising is
example_text <- tweet_data$text[1]

quanteda::tokens(example_text, "word")

tokens(example_text, "sentence")


### create text corpus
tweet_corpus <- corpus(tweet_data)

# example: corpus object is easy to subset in order to get partial data
summary(corpus_subset(tweet_corpus, date > as_date('2016-07-01')), n =nrow(tweet_data))

# checking context of a chosen word 
kwic(tweet_corpus, "terror")
kwic(tweet_corpus, "immigrant*")
kwic(tweet_corpus, "famil*")
kwic(tweet_corpus, "amp") #ampersands!


## exploratory data vis ####
# visualize number and length of tweets 

#summary of quanteda corpus includes numbers of tokens and sentences, but not acutal tokens
#we can do analysis on this
tweet_summary <- summary(tweet_corpus, n =nrow(tweet_data))

str(tweet_summary)
head(tweet_summary)

tweet_summary_tbl <- tweet_summary %>% 
  group_by(author, date) %>% 
  summarize(no_tweets = n_distinct(Text),
            avg_words = mean(Tokens),
            avg_sentences = mean(Sentences))

tweet_summary_tbl %>% 
  ggplot(aes(x = date, y = no_tweets, fill = author, colour = author)) +
  geom_line() +
  geom_point() 


tweet_summary_tbl %>% 
  ggplot(aes(x = date, y = avg_words, fill = author, colour = author)) +
  geom_line() +
  geom_point() 


tweet_summary_tbl %>% 
  ggplot(aes(x = date, y = avg_sentences, fill = author, colour = author)) +
  geom_line() +
  geom_point() 


# look by hour of the day- they both have a diurnal pattern, 
# DT seems to tweet later and then earlier & HC tweets many around midnight
# Potential time zone issues 

tweet_summary_tbl2 <- tweet_summary %>% 
  group_by(author, hour) %>% 
  summarize(no_tweets = n_distinct(Text),
            avg_words = mean(Tokens),
            avg_sentences = mean(Sentences)) 

tweet_summary_tbl2 %>%
  ggplot(aes(x = hour, y = no_tweets, fill = author, colour = author)) +
  geom_line() +
  geom_point() 


# create DFM
my_dfm <- dfm(tweet_corpus)
my_dfm[1:10, 1:5]

# top features 
topfeatures(my_dfm, 50)

# text cleaning
# edit tweets - remove URLs
edited_dfm <- dfm(tweet_corpus, remove_url = TRUE, remove_punct = TRUE, remove = stopwords("english"))
topfeatures(edited_dfm, 20)


#### creating wordclouds ####
set.seed(100)
textplot_wordcloud(edited_dfm, 
                   min.freq = 40, 
                   random.order = FALSE, 
                   rot.per = .25, 
                   colors = RColorBrewer::brewer.pal(8,"Dark2"))


### getting a wordcloud by author
## grouping by author - see differences!!!!
by_author_dfm <- dfm(tweet_corpus,
                     groups = "author",
                     remove = stopwords("english"), remove_punct = TRUE, remove_url = TRUE)

by_author_dfm[1:2,1:10]


# wordcloud by author 
set.seed(200)
textplot_wordcloud(by_author_dfm,
                   comparison = TRUE,
                   min.freq = 50,
                   random.order = FALSE,
                   rot.per = .25, 
                   colors = RColorBrewer::brewer.pal(8,"Dark2"))


#### modelling- split train and test, model and predict ####

# wrapping-up text preprocessing in one function
get_matrix <- function(df){
  corpus <- quanteda::corpus(df)
  dfm <- quanteda::dfm(corpus, remove_url = TRUE, remove_punct = TRUE,     remove = stopwords("english"))
}


#### separate the train and test set ####

# splitting data into train & text
# usually we would use caret for balanced, but it is a large package for a workshop 
set.seed(32984)
trainIndex <- sample.int(n = nrow(tweet_data), 
                         size = floor(.8*nrow(tweet_data)), replace = F)

train_dfm <- get_matrix(tweet_data$text[trainIndex])
train_raw <- tweet_data[, c("text", "tweet_num")][as.vector(trainIndex), ]
train_labels <- tweet_data$author[as.vector(trainIndex)] == "realDonaldTrump"

test_dfm <- get_matrix(tweet_data$text[-trainIndex])
test_raw <- tweet_data[, c("text", "tweet_num")][-as.vector(trainIndex), ]
test_labels <- tweet_data$author[-as.vector(trainIndex)] == "realDonaldTrump"


#### make sure that train & test sets have exactly same features
test_dfm <- dfm_select(test_dfm, train_dfm)


### Naive Bayes model using quanteda::textmodel_nb ####
nb_model <- quanteda::textmodel_nb(train_dfm, train_labels)
nb_preds <- predict(nb_model, test_dfm) 


# compare predictions to actual label
predictions_tbl <- data.frame(predict_label = nb_preds$nb.predicted,
                              actual_label = test_labels,
                              tweet_name = rownames(nb_preds$posterior.prob)
) %>%
  mutate(tweet_num = 
           as.integer(
             str_trim(
               str_replace_all(tweet_name, "text", ""))
           )) 

# select only correct predictions
correct_pred <- predictions_tbl %>%
  filter(actual_label == predict_label) 

# pick a sample of tweets for explainer 
tweets_to_explain <- test_raw %>%
  filter(tweet_num %in% correct_pred$tweet_num) %>% 
  head(6)


# check the model type
class(nb_model)

### set up correct model class and predict functions 
model_type.textmodel_nb <- function(x, ...) {
  return("classification")
}


# have to modify the textmodel_nb_fitted so that is accepted by LIME
predict_model.textmodel_nb <- function(x, newdata, type, ...) {
  X <- dfm_select(dfm(newdata), x$data$x)   
  res <- predict(x, newdata = X, ...)
  switch(
    type,
    raw = data.frame(Response = res$nb.predicted, stringsAsFactors = FALSE),
    prob = as.data.frame(res$posterior.prob, check.names = FALSE)
  )  
}

### run the explainer 
explainer <- lime(train_raw$text, 
                  model = nb_model,
                  preprocess = get_matrix) 


corr_explanation <- lime::explain(tweets_to_explain$text, 
                                  explainer, 
                                  n_labels = 1,
                                  n_features = 6,
                                  cols = 2,
                                  verbose = 0)

#sneak peak into the explanations 
corr_explanation[1:10, 1:10]


# explanation vis
plot_features(corr_explanation)