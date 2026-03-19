#!/bin/bash

set -eo

# Uncomment for debugging
# set -x

#########################################
# SETUP VARIABLES AND DEFAULTS #
#########################################
if [[ -z "$DEPLOY_PATH" || "$DEPLOY_PATH" == "/" || ! "$DEPLOY_PATH" =~ ^[a-zA-Z0-9/_\.\-]+$ || "$DEPLOY_PATH" != */* ]]; then
  echo "✗ DEPLOY_PATH is invalid or unsafe: '$DEPLOY_PATH'"
  exit 1
fi

#########################################
# PREPARE DEPLOYMENT PACKAGE #
#########################################

echo "➤ Preparing deployment package..."

# Set the source directory to wp-content
SOURCE_DIR="$GITHUB_WORKSPACE"
DEPLOY_DIR="$GITHUB_WORKSPACE"
rm -rf "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"

# Always ensure .distignore exists
[[ -f "$GITHUB_WORKSPACE/.distignore" ]] || {
  echo "ℹ︎ .distignore not found, creating an empty one"
  touch "$GITHUB_WORKSPACE/.distignore"
}

# Copy files excluding patterns (using rsync locally)
rsync -av \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='.gitignore' \
  --exclude='.gitattributes' \
  --exclude='.gitmodules' \
  --exclude='.editorconfig' \
  --exclude='.distignore' \
  --exclude='node_modules/' \
  --exclude='/uploads/' \
  --exclude='/upgrade/' \
  --exclude='/backups/' \
  --exclude='/cache/' \
  --exclude='advanced-cache.php' \
  --exclude='object-cache.php' \
  --exclude='db.php' \
  --exclude='*.log' \
  --exclude='*.sql' \
  --exclude='*.sqlite' \
  --exclude='*.db' \
  --exclude-from="$SOURCE_DIR/.distignore" \
  "$SOURCE_DIR/" "$DEPLOY_DIR/"

echo "✓ Deployment package prepared."
echo "ℹ︎ Total files to deploy: $(find "$DEPLOY_DIR" -type f | wc -l)"

#########################################
# PREPARE REMOTE PATH #
#########################################

echo "➤ Preparing remote path..."
if ssh server "mkdir -p '$DEPLOY_PATH'"; then
  echo "✓ Remote path ensured."
else
  echo "✗ Failed to create remote path. Exiting..."
  exit 1
fi

#########################################
# DEPLOY FILES VIA SCP #
#########################################

echo "➤ Deploying files via SCP..."

# Create a tar archive for faster transfer
cd "$DEPLOY_DIR"
tar -czf ../deploy.tar.gz .
cd ..

# Upload the tar file
if scp -o StrictHostKeyChecking=no deploy.tar.gz server:"$DEPLOY_PATH/"; then
  echo "✓ Archive uploaded successfully."
else
  echo "✗ SCP upload failed"
  exit 1
fi

# Extract on remote server and cleanup
echo "➤ Extracting files on remote server..."
ssh server "cd '$DEPLOY_PATH' && tar -xzf deploy.tar.gz && rm -f deploy.tar.gz"

if [ $? -eq 0 ]; then
  echo "✓ Files extracted successfully!"
else
  echo "✗ Extraction failed"
  exit 1
fi

# Cleanup local files
rm -f deploy.tar.gz
rm -rf "$DEPLOY_DIR"

#########################################
# FLUSH CACHES IF WP-CLI IS AVAILABLE #
#########################################

echo "➤ Checking for WP-CLI and flushing caches..."

ssh server "cd '$DEPLOY_PATH' && if command -v wp >/dev/null 2>&1; then
  echo 'ℹ︎ WP-CLI found. Flushing caches...'
  wp cache flush --allow-root || true
  wp transient delete --all --allow-root || true
  wp rewrite flush --hard --allow-root || true
  echo '✓ Cache flush completed.'
else
  echo 'ℹ︎ WP-CLI not found. Skipping cache flush.'
fi"

#########################################
# FINAL SUMMARY #
#########################################

echo "✓ Deployment process finished."
