# R script with errors
# Test: Error handling and stderr capture

cat("Starting script with errors...\n")

# This will work
cat("Step 1: Working code\n")
x <- 1:5
print(x)

# This will cause an error
cat("Step 2: About to cause an error...\n")
stop("This is an intentional error for testing!")

# This won't be executed
cat("Step 3: This should not appear\n")
