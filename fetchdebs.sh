#!/bin/bash

# fetch_packages.sh - Downloads packages and their dependencies for offline installation
# Usage: ./fetch_packages.sh package_list.txt [output_directory]

set -e  # Exit on error

# Check if package list file was provided
if [ $# -lt 1 ]; then
    echo "Usage: $0 package_list.txt [output_directory]"
    echo "  package_list.txt: File containing one package name per line"
    echo "  output_directory: Directory to store downloaded packages (default: ./debian-packages)"
    exit 1
fi

PACKAGE_LIST="$1"
OUTPUT_DIR="${2:-./debian-packages}"
DEPS_DIR="${OUTPUT_DIR}/dependencies"
LOG_FILE="${OUTPUT_DIR}/download.log"
PROCESSED_FILE="${OUTPUT_DIR}/processed.txt"
CURRENT_DIR=$(pwd)

# Check if package list file exists
if [ ! -f "$PACKAGE_LIST" ]; then
    echo "Error: Package list file '$PACKAGE_LIST' not found."
    exit 1
fi

# Create output directories
mkdir -p "$OUTPUT_DIR" "$DEPS_DIR"
touch "$PROCESSED_FILE"

echo "$(date) - Starting package download process" | tee -a "$LOG_FILE"
echo "Package list: $PACKAGE_LIST" | tee -a "$LOG_FILE"
echo "Output directory: $OUTPUT_DIR" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"

# Function to get all dependencies for a package
get_dependencies() {
    local pkg="$1"
    local deps
    
    # Get direct dependencies
    deps=$(apt-cache depends "$pkg" 2>/dev/null | 
           grep '^\s*Depends:\|^\s*Pre-Depends:|^\s*\w' | 
           sed 's/^\s*Depends: //' |
           sed 's/^\s*Pre-Depends: //' |
           sed 's/<//;s/>//' |
           grep -v '^$')
    
    echo "$deps"
}

# Function to process a package and its dependencies recursively
process_package() {
    local pkg="$1"
    # Remove any trailing newlines or whitespace
    pkg=$(echo "$pkg" | tr -d '\n\r' | xargs)
    local depth="$2"
    local indent=""
    
    # Create indent based on depth
    for ((i=0; i<depth; i++)); do
        indent="$indent  "
    done
    
    # Skip if package has already been processed
    if grep -q "^$pkg$" "$PROCESSED_FILE"; then
        echo "${indent}Package $pkg already processed, skipping..."
        return 0
    fi
    
    echo "${indent}Processing package: $pkg" | tee -a "$LOG_FILE"
    
    # Mark package as processed
    echo "$pkg" >> "$PROCESSED_FILE"
    
    # Download the package
    echo "${indent}Downloading $pkg a..." | tee -a "$LOG_FILE"
    if apt-get download "$pkg" >> "$LOG_FILE" 2>&1; then
        # Move the downloaded package to the output directory
        mv *.deb "$OUTPUT_DIR/" 2>/dev/null || true
        echo "${indent}✓ Downloaded $pkg" | tee -a "$LOG_FILE"
    else
        echo "${indent}✗ Failed to download $pkg" | tee -a "$LOG_FILE"
    fi
    
    # Get dependencies
    local deps=$(get_dependencies "$pkg")
    
    # Process each dependency
    for dep in $deps; do
        # Also trim dependency names
        dep=$(echo "$dep" | tr -d '\n\r' | xargs)
        process_package "$dep" $((depth + 1))
    done
}

# Main processing loop
total_packages=$(wc -l < "$PACKAGE_LIST")
current=0

echo "Found $total_packages packages in list" | tee -a "$LOG_FILE"

while read -r package; do
    # Skip empty lines and comments
    [[ -z "$package" || "$package" =~ ^# ]] && continue
    
    current=$((current + 1))
    echo "[$current/$total_packages] Processing main package: $package" | tee -a "$LOG_FILE"
    
    # Process the package and its dependencies
    process_package $package 0
    
    echo "Completed processing $package and its dependencies" | tee -a "$LOG_FILE"
    echo "==================================================" | tee -a "$LOG_FILE"
done < "$PACKAGE_LIST"

# Create repository files
echo "Creating repository metadata..." | tee -a "$LOG_FILE"
cd "$OUTPUT_DIR"

# Create proper repository structure
mkdir -p dists/stable/main/binary-amd64

# Move all .deb packages to a pool directory structure
mkdir -p pool/main
find . -maxdepth 1 -name "*.deb" -exec mv {} pool/main/ \;

# Generate Packages files
dpkg-scanpackages pool/main /dev/null > dists/stable/main/binary-amd64/Packages
gzip -9c dists/stable/main/binary-amd64/Packages > dists/stable/main/binary-amd64/Packages.gz

# Create Release file with proper distribution information
cd dists/stable
cat > Release <<EOF
Origin: Local Repository
Label: Local
Suite: stable
Codename: stable
Architectures: amd64
Components: main
Description: Local package repository
Date: $(date -R)
EOF

# Append the checksums section to the Release file
apt-ftparchive release . >> Release
cd "$CURRENT_DIR"

echo "==================================================" | tee -a "$LOG_FILE"
echo "Package download complete!" | tee -a "$LOG_FILE"
echo "Total unique packages downloaded: $(find "$OUTPUT_DIR" -name "*.deb" | wc -l)" | tee -a "$LOG_FILE"
echo "Output directory: $OUTPUT_DIR" | tee -a "$LOG_FILE"
echo "==================================================" | tee -a "$LOG_FILE"
echo "To set up the repository on the offline machine, run:" | tee -a "$LOG_FILE"
echo "  sudo mkdir -p /opt/local-repo" | tee -a "$LOG_FILE"
echo "  sudo cp -r \"$OUTPUT_DIR\"/* /opt/local-repo/" | tee -a "$LOG_FILE"
echo "  echo \"deb [trusted=yes] file:/opt/local-repo stable main\" | sudo tee /etc/apt/sources.list.d/local-repo.list" | tee -a "$LOG_FILE"
echo "  sudo apt-get update" | tee -a "$LOG_FILE"
echo "  sudo apt-get install <package-name>" | tee -a "$LOG_FILE"