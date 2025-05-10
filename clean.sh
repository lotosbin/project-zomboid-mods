#!/bin/bash

# Delete all .DS_Store files recursively
find . -name ".DS_Store" -type f -delete

# Remove all .vscode directories recursively 
find . -name ".vscode" -type d -exec rm -rf {} +
