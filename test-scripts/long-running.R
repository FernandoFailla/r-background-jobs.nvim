# Long-running R script
# Test: Job duration tracking and real-time output

cat("Starting long-running job...\n")

for (i in 1:10) {
  cat(sprintf("Step %d/10 - Processing...\n", i))
  Sys.sleep(2)  # Sleep for 2 seconds
  
  # Perform some calculation
  result <- sum(rnorm(1000))
  cat(sprintf("  Result: %.4f\n", result))
}

cat("Long-running job completed!\n")
