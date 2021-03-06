################################################################################################
# Building an Interpretable NLP model to classify tweets Workshop
# full code 
# eRum 2018, Budapest 
################################################################################################


# load packages ####
library(readr)
library(quanteda)
library(dplyr)
library(stringr)
library(lubridate)
library(ggplot2)
library(caret)
library(tidytext)
library(glmnet)
library(tm)
library(wordcloud)
library(devtools)
library(xgboost)
library(text2vec)

## load data ####
tweet_csv <- read_csv("tweets.csv")
str(tweet_csv, give.attr = FALSE)

## data exploration ####
# see original authors
sort(table(tweet_csv$original_author), decreasing = TRUE)
table(tweet_csv$lang)
table(tweet_csv$handle, tweet_csv$lang)
table(tweet_csv$handle)
table(tweet_csv$handle, tweet_csv$is_retweet)
table(tweet_csv$is_retweet, is.na(tweet_csv$original_author))

### data cleaning 
tweet_data <- tweet_csv %>% 
#  filter(is_retweet == "False") %>%
  select(author = handle, text, retweet_count, favorite_count, source_url, timestamp = time) %>% 
  mutate(date = as_date(str_sub(timestamp, 1, 10)),
         hour = hour(hms(str_sub(timestamp, 12, 19))),
         tweet_num = row_number()
  ) %>% select(-timestamp)

str(tweet_data)
tweet_data %>%
  select(-c(text, source_url)) %>%
  head()

table(tweet_data$author)

#### TIDYTEXT APPROACH ####

#show what tokenising is
example_text <- tweet_data %>%
  select(text) %>%
  slice(1)

example_text %>%
  tidytext::unnest_tokens(sentence, text, token = "words")

example_text %>%
  tidytext::unnest_tokens(sentence, text, token = "sentences")

# data exploration ####

# who tweets more over time
tweet_data %>% 
  group_by(author, date) %>% 
  summarise(tweet_num = n_distinct(text)) %>%
  ggplot(aes(date, tweet_num, colour = author, group = author)) +
  geom_line() +
  theme_minimal()


# who tweets when 
tweet_data %>% 
  group_by(author, hour) %>% 
  summarise(tweet_num = n_distinct(text)) %>%
  ggplot(aes(hour, tweet_num, colour = author, group = author)) +
  geom_line() +
  theme_minimal()


# who writes longer tweets?
sentence_data <- tweet_data %>% 
  select(tweet_num, text) %>% 
  tidytext::unnest_tokens(sentence, text, token = "sentences")
 
head(sentence_data)
sentence_data[1:6, 2] 


word_data <- tweet_data %>% 
  select(tweet_num, text) %>% 
  tidytext::unnest_tokens(word, text, token = "words")


head(word_data)

sentences_count <- sentence_data %>% 
  group_by(tweet_num) %>% 
  summarise(n_sentences = n_distinct(sentence))

head(sentences_count)

word_count <- word_data %>% 
  group_by(tweet_num) %>% 
  summarise(n_words = n_distinct(word))

head(word_count)

## avg sentences per author  
tweet_data %>% 
  inner_join(sentences_count) %>% 
  group_by(author, date) %>% 
  summarise(avg_sentences  = mean(n_sentences)) %>% 
  ggplot(aes(date, avg_sentences, group = author, color = author)) +
    geom_line() +
    theme_minimal()
  

# avg words per author
tweet_data %>% 
  inner_join(word_count) %>% 
  group_by(author, date) %>% 
  summarise(avg_words = mean(n_words)) %>% 
  ggplot(aes(date, avg_words, group = author, color = author)) +
  geom_line() +
  theme_minimal()

### wordclouds
word_data %>%
  #anit_join(stopwords) %>%
  count(word) %>%
  with(wordcloud(word, n, max.words = 100))

tweet_data %>% 
  inner_join(word_data) %>% 
  group_by(author) %>% 
  count(word) %>%
  mutate(colorSpecify = ifelse(author == "HillaryClinton", "blue", "red")) %>%
  with(wordcloud(word, n, max.words = 100,
          colors = colorSpecify, ordered.colors=TRUE))

#### format data for modelling ####

tweet_dtm = word_data %>% 
  #select(tweet_num, word) %>%  
  count(tweet_num, word) %>%
  cast_dtm(tweet_num, word, n)

dim(tweet_dtm)
tweet_dtm[1:6, 1:6]
tweet_dtm[1:6, 1:6]$dimnames

# create train and test data sets
indexes <- createDataPartition(tweet_data$author, times = 1,
                               p = 0.7, list = FALSE)


### creating meta data 
#meta <- data.frame(tweet_num = as.integer(dimnames(tweet_dtm)[[1]])) %>%
##  left_join(word_data[!duplicated(word_data$tweet_num), ], by = "tweet_num") %>%
#  mutate(response = as.numeric(author == "realDonaldTrump")) %>% 
#  select(-author)

#meta <- data.frame(id = dimnames(papers_dtm)[[1]]) %>%
#  left_join(papers_words[!duplicated(papers_words$id), ], by = "id") %>%
#  mutate(y = as.numeric(author == "hamilton"),
#         train = author != "unknown")




# word tokenization and dtm creation
word_dtm <- function(df){
  df %>% 
  select(tweet_num, author, text) %>% 
    #tidytext::unnest_tokens(word, text, token = "tweets", strip_url = TRUE, strip_punct = TRUE) %>% 
    tidytext::unnest_tokens(word, text) %>% 
    count(tweet_num, word, sort = TRUE) %>%
    cast_dtm(tweet_num, word, n)
}



word_m <- function(df){
  df %>% 
    select(tweet_num, author, text) %>% 
    #tidytext::unnest_tokens(word, text, token = "tweets", strip_url = TRUE, strip_punct = TRUE) %>% 
    tidytext::unnest_tokens(word, text) %>% 
    count(tweet_num, word, sort = TRUE) %>%
    cast_sparse(tweet_num, word, n)
}


set.seed(1)
indexes <- createDataPartition(tweet_data$author, times = 1,
                              p = 0.7, list = FALSE)

# can't partition on 'total' dtm straight away as the author is not available there

#tweet_m <- word_m(tweet_data)
#nrow(tweet_m)

#train_index <- sample(1:nrow(tweet_m), 0.8 * nrow(tweet_m))
#test_index <- setdiff(1:nrow(tweet_m), train_index)

#train_m <- tweet_m[train_data, ]
#test_m <- word_m(test_data)

train_data <- tweet_data[indexes, ]
test_data <- tweet_data[-indexes, ]


#set.seed(1)
train_m <- word_m(train_data)
test_m <- word_m(test_data)



#train_dtm <- word_dtm(train_data)
#test_dtm <- word_dtm(test_data)

#tidy(train_dtm)
#tidy(test_dtm)

# train a glmnet model and create predictions ####


#dtm_train <- get_matrix(train_tweets$text)
#dtm_test <- get_matrix(test_tweets$text)
#train_labels <- train_tweets$author == "realDonaldTrump"

train_m[1:6, 1:6]
attributes(train_m)$Dimnames[[1]]

# extract Docs attribute from matrix to match correct labels and create labels vector for modelling 
#create_labels = function(matrix){
#  response = data.frame(tweet_num = as.integer(attributes(matrix)$Dimnames[[1]])) %>% 
#    left_join(select(tweet_data, tweet_num, author)) %>% 
#    mutate(response = as.numeric(author == "realDonaldTrump")) %>% 
#    select(response) %>% 
#    pull() }


#train_predictors  <- train_dtm %>% as.matrix()
train_m
test_m

#test_predictors <- test_dtm %>% as.matrix()
#train_labels = create_labels(train_m)
#test_labels = create_labels(test_m)

#length(train_labels)
#length(test_labels)

dim(train_m)
dim(test_m)

set.seed(1234)
glm_model <- glmnet(train_m, train_data$author=="realDonaldTrump", family = "binomial")
glm_preds <- predict(glm_model, test_m) > 0.5 ## Julia, help! doesn't run because of wrong dimensions!

test_m[1:6, 1:6]
dim(train_m)
dim(test_m)

# Accuracy
mean(glm_preds == test_labels)





## xgboost ####

param <- list(max_depth = 7, 
              eta = 0.1, 
              objective = "binary:logistic", 
              eval_metric = "error", 
              nthread = 1)

set.seed(1234)
xgb_model <- xgb.train(
  param, 
  xgb.DMatrix(train_m, label = train_data$author == "realDonaldTrump"),
  nrounds = 50,
  verbose=0
)

dim(train_data)
dim(train_m)

# We use a (standard) threshold of 0.5
xgb_preds <- predict(xgb_model, test_m) > 0.5

# Accuracy
print(mean(xgb_preds == test_labels)) # much lower accuracy than before :/


### SVM ####
library(e1071)
library(SparseM)

svm_model <- e1071::svm(train_m, as.numeric(train_labels), kernel='linear')
svm_preds <- predict(svm_model, test_m) > 0.5

# Accuracy
print(mean(svm_preds == test_labels))




#### QUANTEDA APPROACH ####
### create text corpus and the summary of it 
#(inlcudes numbers of tokens and sentences, but not acutal tokens)
tweet_corpus <- corpus(tweet_data)
tweet_summary <- summary(tweet_corpus, n =nrow(tweet_data))
str(tweet_summary)


# subsetting corpus
summary(corpus_subset(tweet_corpus, date > as_date('2016-07-01')), n =nrow(tweet_data))


# checking context of a chosen word 

kwic(tweet_corpus, "terror")
kwic(tweet_corpus, "immigrant*")
kwic(tweet_corpus, "famil*")


## exploratory data vis ####
# visualize number and length of tweets 

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


# look by hour of the day- they both have a diurnal pattern, but DT seems to tweet later and then earlier. 
#HC tweets many around midnight 
if("hour" %in% names(tweet_summary)) {
tweet_summary_tbl2 <- tweet_summary %>% 
  group_by(author, hour) %>% 
  summarize(no_tweets = n_distinct(Text),
            avg_words = mean(Tokens),
            avg_sentences = mean(Sentences)) 

tweet_summary_tbl2 %>%
  ggplot(aes(x = hour, y = no_tweets, fill = author, colour = author)) +
  geom_line() +
  geom_point() 
}

# create DFM
my_dfm <- dfm(tweet_corpus)
my_dfm[1:10, 1:5]

# top features 
topfeatures(my_dfm, 20)

# text cleaning
# edit tweets - remove URLs
edited_dfm <- dfm(tweet_corpus, remove_url = TRUE, remove_punct = TRUE, remove = stopwords("english"))
topfeatures(edited_dfm, 20)


# getting a wordcloud
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
set.seed(100)
#?textplot_wordcloud
textplot_wordcloud(by_author_dfm,
                   comparison = TRUE,
                   min.freq = 50,
                   random.order = FALSE,
                   rot.per = .25, 
                   colors = RColorBrewer::brewer.pal(8,"Dark2"))


#### modelling ####

#### separate the train and test set - QUANTEDA way ####

edited_dfm[1:10, 1:10]
table(tweet_data$author)

0.8*6444

train_dfm <- edited_dfm[1: 5156, ]
train_raw <- tweet_data[1: 5156, ]
train_labels <- train_raw$author == "realDonaldTrump"
table(train_raw$author)


#### TO DO: needs to be randomised! ####
test_dfm <- edited_dfm[5157:nrow(tweet_data), ]
test_raw <- tweet_data[5157:nrow(tweet_data), ]
test_labels <- test_raw$author == "realDonaldTrump"
table(test_raw$author)


# turn to sparse matrix 
test_dfm[1:10, 1:10]
??sparseMatrix
sparseMatrix(test_dfm)
??xgb.DMatrix

# compare dimensions 
dim(test_raw)
test_dfm
train_dfm

### Naive Bayes model - works and it's fast!
nb_model <- quanteda::textmodel_nb(train_dfm, train_raw$author=="realDonaldTrump")
nb_preds <- predict(nb_model, test_dfm) #> 0.5

# Accuracy
print(mean(nb_preds$nb.predicted == test_labels))


### XGBoost model

train_dtm <- convert(train_dfm, "tm")
train_m <- convert(train_dfm, "matrix")
test_m <- convert(test_dfm, "matrix")

dim(train_m)
length(train_labels)

param <- list(max_depth = 7, 
              eta = 0.1, 
              objective = "binary:logistic", 
              eval_metric = "error", 
              nthread = 1)

set.seed(1234)
xgb_model <- xgb.train(
  param, 
  xgb.DMatrix(train_m, label = train_label),
  nrounds = 50,
  verbose=0
)


# We use a (standard) threshold of 0.5
xgb_preds <- predict(xgb_model, test_m) > 0.5
#test_labels <- test_tweets$author == "realDonaldTrump"

# Accuracy
print(mean(xgb_preds == test_label))

### penalised logistic regression
library(glmnet)

set.seed(1234)
glm_model <- glmnet(train_dfm, train_label, family = "binomial")

# We use a (standard) threshold of 0.5
glm_preds <- predict(glm_model, test_dfm) > 0.5

# Accuracy
print(mean(glm_preds == test_label))



#### separate the train and test set - CARET way ####

tweets_tokens <- cbind(Label = tweet_data$author, data.frame(edited_dfm)) %>%
  mutate(Label = as.factor(ifelse(Label == "HillaryClinton", 1, 0))) %>%
  mutate(Label = as.factor(Label)) %>%
  select(-document)

str(tweets_tokens)

set.seed(32984)
indexes <- createDataPartition(tweets_tokens$Label, times = 1,
                               p = 0.7, list = FALSE)

trainData <- tweets_tokens[indexes,]
testData <- tweets_tokens[-indexes,]
str(trainData)

#### train the model with dfm ####
# random forest not suitable for text classification - doesn't deal well with high-dimensional, sparse data, SVM or naive bayes are a better start
# http://fastml.com/classifying-text-with-bag-of-words-a-tutorial/
# other algos take too long to train

# time your model
library(microbenchmark)

?microbenchmark
microbenchmark(nb_model <- train(Label ~ ., data = trainData, method = 'nb'), times = 2)
system.time({ nb_model <- train(Label ~ ., data = trainData, method = 'nb') })

### train using text2vec DTM ####

library(text2vec) 
library(qdapRegex)

str(tweet_csv)

all_tweets <- tweet_csv %>% 
  filter(str_to_lower(is_retweet) == "false") %>% 
  rename(author = handle) %>% 
  select(author, text) %>% 
  mutate(text = qdapRegex::rm_url(text)) %>% #removes URLs from text
  na.omit()

table(all_tweets$author)

# splitting data into train & text
set.seed(32984)
trainIndex <- createDataPartition(all_tweets$author, p = .8, 
                                  list = FALSE, 
                                  times = 1)

train_tweets <- all_tweets[ trainIndex,]
test_tweets <- all_tweets[ -trainIndex,]

# tokenization & creating a dtm
get_matrix <- function(text) {
  it <- itoken(text, progressbar = TRUE)
  create_dtm(it, vectorizer = hash_vectorizer())
}


dtm_train <- get_matrix(train_tweets$text)
dtm_test <- get_matrix(test_tweets$text)
train_labels <- train_tweets$author == "realDonaldTrump"

####  xgboost ####

library(xgboost) 


param <- list(max_depth = 7, 
              eta = 0.1, 
              objective = "binary:logistic", 
              eval_metric = "error", 
              nthread = 1)

set.seed(1234)
xgb_model <- xgb.train(
  param, 
  xgb.DMatrix(dtm_train, label = train_labels),
  nrounds = 50,
  verbose=0
)


# We use a (standard) threshold of 0.5
xgb_preds <- predict(xgb_model, dtm_test) > 0.5
test_labels <- test_tweets$author == "realDonaldTrump"


# Accuracy
print(mean(xgb_preds == test_labels))


# other than xgboost models ####

### logistic regressin using glmnet

library(glmnet)

set.seed(1234)
glm_model <- glmnet(dtm_train, train_labels, family = "binomial")

# We use a (standard) threshold of 0.5
glm_preds <- predict(glm_model, dtm_test) > 0.5

# Accuracy
print(mean(glm_preds == test_labels))


### SVM
library(e1071)
library(SparseM)

svm_model <- e1071::svm(dtm_train, as.numeric(train_labels), kernel='linear')
svm_preds <- predict(svm_model, dtm_test) > 0.5

#library(sparseSVM)
#ssvm_model <- cv.sparseSVM(dtm_train, as.numeric(train_labels))

# Accuracy
print(mean(glm_preds == test_labels))


### LIME on glmnet model ####

# select only correct predictions
predictions_tbl <- glm_preds2 %>% 
  as_tibble() %>% 
  rename_(predict_label = names(.)[1]) %>%
  tibble::rownames_to_column()

correct_pred <- test_tweets %>%
  tibble::rownames_to_column() %>% 
  mutate(test_label = author == "realDonaldTrump") %>%
  left_join(predictions_tbl) %>%
  filter(test_label == predict_label) %>% 
  pull(text) %>% 
  head(4) # Julia, help! it needs to be 5 or less, otherwise corr_explanation returns an error, why?

str(correct_pred)

detach("package:dplyr", unload=TRUE)

library(lime)

explainer <- lime(correct_pred, 
                  model = xgb_model, 
                  preprocess = get_matrix)

corr_explanation <- lime::explain(correct_pred, 
                                  explainer, 
                                  n_labels = 1, n_features = 6, cols = 2, verbose = 0)
plot_features(corr_explanation)


