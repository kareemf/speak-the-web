#!/bin/bash
#
# Image Optimization Script for Speak the Web
# Optimizes PNG images from docs/images/originals/ to docs/images/
#
# Requirements: pngquant (brew install pngquant)
#
# Usage: ./scripts/optimize-images.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ORIGINALS_DIR="$PROJECT_ROOT/docs/images/originals"
OUTPUT_DIR="$PROJECT_ROOT/docs/images"

# Image settings
MAX_WIDTH=600
QUALITY="75-90"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🖼️  Image Optimization Script"
echo "=============================="
echo ""

# Check for pngquant
if ! command -v pngquant &> /dev/null; then
    echo -e "${RED}Error: pngquant is not installed.${NC}"
    echo "Install it with: brew install pngquant"
    exit 1
fi

# Check for sips (macOS built-in)
if ! command -v sips &> /dev/null; then
    echo -e "${RED}Error: sips is not available (macOS only).${NC}"
    exit 1
fi

# Check that originals directory exists
if [ ! -d "$ORIGINALS_DIR" ]; then
    echo -e "${RED}Error: Originals directory not found: $ORIGINALS_DIR${NC}"
    echo "Place your original images in docs/images/originals/"
    exit 1
fi

echo "📁 Source: $ORIGINALS_DIR"
echo "📁 Output: $OUTPUT_DIR"
echo "📐 Max width: ${MAX_WIDTH}px"
echo "🎨 Quality: $QUALITY"
echo ""

# Count images to process
cd "$ORIGINALS_DIR"
IMAGE_COUNT=$(find . -maxdepth 1 -type f \( -name "*.png" -o -name "*.PNG" \) | wc -l | tr -d ' ')

if [ "$IMAGE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No images found in originals/.${NC}"
    exit 0
fi

echo "Found $IMAGE_COUNT image(s) to process"
echo ""

# Calculate original size
ORIGINAL_SIZE=$(du -sh "$ORIGINALS_DIR" 2>/dev/null | cut -f1)
echo "📊 Original size: $ORIGINAL_SIZE"
echo ""

# Process each image
shopt -s nullglob
for file in *.png *.PNG; do
    # Skip if no matches
    [ -f "$file" ] || continue

    # Normalize filename to lowercase .png
    BASENAME=$(basename "$file")
    OUTNAME="${BASENAME%.PNG}"
    OUTNAME="${OUTNAME%.png}.png"
    OUTPATH="$OUTPUT_DIR/$OUTNAME"

    echo -e "${YELLOW}Processing: $BASENAME → $OUTNAME${NC}"

    # Get original file size
    BEFORE_SIZE=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)

    # Copy to output, resize, then compress
    cp "$file" "$OUTPATH"

    # Resize to max width (maintains aspect ratio)
    sips -Z "$MAX_WIDTH" "$OUTPATH" --out "$OUTPATH" > /dev/null 2>&1
    echo "  ✓ Resized to max ${MAX_WIDTH}px width"

    # Compress with pngquant
    pngquant --quality="$QUALITY" --force --ext .png "$OUTPATH" 2>/dev/null || true
    echo "  ✓ Compressed with pngquant (quality $QUALITY)"

    # Get new file size
    AFTER_SIZE=$(stat -f%z "$OUTPATH" 2>/dev/null || stat -c%s "$OUTPATH" 2>/dev/null)

    # Calculate reduction percentage
    if [ "$BEFORE_SIZE" -gt 0 ]; then
        REDUCTION=$(echo "scale=1; (1 - $AFTER_SIZE / $BEFORE_SIZE) * 100" | bc)
        echo -e "  ${GREEN}✓ Reduced by ${REDUCTION}% ($(echo "scale=0; $AFTER_SIZE / 1024" | bc)KB)${NC}"
    fi

    echo ""
done

# Calculate final size
FINAL_SIZE=$(du -sh "$OUTPUT_DIR" --exclude=originals 2>/dev/null | cut -f1 || du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)

echo "=============================="
echo -e "${GREEN}✅ Optimization complete!${NC}"
echo ""
echo "📊 Summary:"
echo "   Originals: $ORIGINAL_SIZE (in originals/)"
echo "   Optimized: Check docs/images/*.png"
echo ""
echo "⚠️  Remember to update HTML references if filenames changed (.PNG → .png)"
