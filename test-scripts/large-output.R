# R script with large output
# Test: Large output handling

cat("Generating large output...\n")

# Generate lots of output
for (i in 1:100) {
  cat(sprintf("Line %d: %s\n", i, paste(rep("x", 50), collapse="")))
  
  if (i %% 10 == 0) {
    cat(sprintf("--- Checkpoint: %d%% complete ---\n", i))
  }
}

# Print a data frame
cat("\nSample data frame:\n")
df <- data.frame(
  id = 1:50,
  value = rnorm(50),
  category = sample(letters[1:5], 50, replace = TRUE)
)
print(df)

cat("\nLarge output test completed!\n")
