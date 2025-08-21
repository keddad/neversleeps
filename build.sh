#!/bin/bash

# Build main page
pandoc index.md -o index.html --standalone --template=templates/template.html

# Build all publications
for file in publications/*.md; do
  base=$(basename "$file" .md)
  pandoc "$file" -o "publications/$base.html" -f markdown-smart --standalone --template=templates/template.html
done