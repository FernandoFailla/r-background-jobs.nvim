# Simple R script that completes quickly
# Test: Basic job execution

cat("Starting simple test...\n")
cat("Current working directory:", getwd(), "\n")
cat("R version:", R.version.string, "\n")

# Simple calculation
x <- 1:10
mean_x <- mean(x)
cat("Mean of 1:10 =", mean_x, "\n")

# Print to stderr as well
message("This is a message to stderr")

cat("Test completed successfully!\n")
